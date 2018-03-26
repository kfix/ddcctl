//
//  DDC.c
//  DDC Panel
//
//  Created by Jonathan Taylor on 7/10/09.
//  See http://github.com/jontaylor/DDC-CI-Tools-for-OS-X
//

#include <IOKit/IOKitLib.h>
#include <IOKit/graphics/IOGraphicsLib.h>
#include <ApplicationServices/ApplicationServices.h>
#include "DDC.h"

#ifndef kMaxRequests
#define kMaxRequests 10
#endif

/*

 Iterate IOreg's device tree to find the IOFramebuffer mach service port that corresponds to a given CGDisplayID
 replaces CGDisplayIOServicePort: https://developer.apple.com/library/mac/documentation/GraphicsImaging/Reference/Quartz_Services_Ref/index.html#//apple_ref/c/func/CGDisplayIOServicePort
 based on: https://github.com/glfw/glfw/pull/192/files
 */
static io_service_t IOFramebufferPortFromCGDisplayID(CGDirectDisplayID displayID)
{
    io_iterator_t iter;
    io_service_t serv, servicePort = 0;

    kern_return_t err = IOServiceGetMatchingServices(kIOMasterPortDefault, IOServiceMatching(IOFRAMEBUFFER_CONFORMSTO), &iter);

    if (err != KERN_SUCCESS)
        return 0;

    // now recurse the IOReg tree
    while ((serv = IOIteratorNext(iter)) != MACH_PORT_NULL)
    {
        CFDictionaryRef info;
        io_name_t	name;
        CFIndex vendorID = 0, productID = 0, serialNumber = 0;
        CFNumberRef vendorIDRef, productIDRef, serialNumberRef;
#ifdef DEBUG
        CFStringRef location = CFSTR("");
        CFStringRef serial = CFSTR("");
#endif
        Boolean success = 0;

        // get metadata from IOreg node
        IORegistryEntryGetName(serv, name);
        info = IODisplayCreateInfoDictionary(serv, kIODisplayOnlyPreferredName);

#ifdef DEBUG
        /* When assigning a display ID, Quartz considers the following parameters:Vendor, Model, Serial Number and Position in the I/O Kit registry */
        // http://opensource.apple.com//source/IOGraphics/IOGraphics-179.2/IOGraphicsFamily/IOKit/graphics/IOGraphicsTypes.h
        CFStringRef locationRef = CFDictionaryGetValue(info, CFSTR(kIODisplayLocationKey));
        if (locationRef) location = CFStringCreateCopy(NULL, locationRef);
        CFStringRef serialRef = CFDictionaryGetValue(info, CFSTR(kDisplaySerialString));
        if (serialRef) serial = CFStringCreateCopy(NULL, serialRef);
#endif
        if (CFDictionaryGetValueIfPresent(info, CFSTR(kDisplayVendorID), (const void**)&vendorIDRef))
            success = CFNumberGetValue(vendorIDRef, kCFNumberCFIndexType, &vendorID);

        if (CFDictionaryGetValueIfPresent(info, CFSTR(kDisplayProductID), (const void**)&productIDRef))
            success &= CFNumberGetValue(productIDRef, kCFNumberCFIndexType, &productID);

        IOItemCount busCount;
        IOFBGetI2CInterfaceCount(serv, &busCount);

        if (!success || busCount < 1 || CGDisplayIsBuiltin(displayID)) {
            // this does not seem to be a DDC-enabled display, skip it
            CFRelease(info);
            continue;
        }
        // if (framebuffer.hasDDCConnect(0)) // https://developer.apple.com/reference/kernel/ioframebuffer/1813510-hasddcconnect?language=objc
        // kAppleDisplayTypeKey -- if this is an Apple display, can use IODisplay func to change brightness: http://stackoverflow.com/a/32691700/3878712

        if (CFDictionaryGetValueIfPresent(info, CFSTR(kDisplaySerialNumber), (const void**)&serialNumberRef))
            CFNumberGetValue(serialNumberRef, kCFNumberCFIndexType, &serialNumber);

        // compare IOreg's metadata to CGDisplay's metadata to infer if the IOReg's I2C monitor is the display for the given NSScreen.displayID
        if (CGDisplayVendorNumber(displayID) != vendorID  ||
            CGDisplayModelNumber(displayID)  != productID ||
            CGDisplaySerialNumber(displayID) != serialNumber) // SN is zero in lots of cases, so duplicate-monitors can confuse us :-/
        {
            CFRelease(info);
            continue;
        }

#ifdef DEBUG
        // considering this IOFramebuffer as the match for the CGDisplay, dump out its information
        // compare with `make displaylist`
        printf("\nFramebuffer: %s\n", name);
        printf("%s\n", CFStringGetCStringPtr(location, kCFStringEncodingUTF8));
        printf("VN:%ld PN:%ld SN:%ld", vendorID, productID, serialNumber);
        printf(" UN:%d", CGDisplayUnitNumber(displayID));
        printf(" IN:%d", iter);
        printf(" Serial:%s\n\n", CFStringGetCStringPtr(serial, kCFStringEncodingUTF8));
#endif
        servicePort = serv;
        CFRelease(info);
        break;
    }

    IOObjectRelease(iter);
    return servicePort;
}

dispatch_semaphore_t DisplayQueue(CGDirectDisplayID displayID) {
    static UInt64 queueCount = 0;
    static struct DDCQueue {CGDirectDisplayID id; dispatch_semaphore_t queue;} *queues = NULL;
    dispatch_semaphore_t queue = NULL;
    if (!queues)
        queues = calloc(50, sizeof(*queues)); //FIXME: specify
    UInt64 i = 0;
    while (i < queueCount)
        if (queues[i].id == displayID)
            break;
        else
            i++;
    if (queues[i].id == displayID)
        queue = queues[i].queue;
    else
        queues[queueCount++] = (struct DDCQueue){displayID, (queue = dispatch_semaphore_create(1))};
    return queue;
}

bool DisplayRequest(CGDirectDisplayID displayID, IOI2CRequest *request) {
    dispatch_semaphore_t queue = DisplayQueue(displayID);
    dispatch_semaphore_wait(queue, DISPATCH_TIME_FOREVER);
    bool result = false;
    io_service_t framebuffer; // https://developer.apple.com/reference/kernel/ioframebuffer
    //if ((framebuffer = CGDisplayIOServicePort(displayID))) { // Deprecated in OSX 10.9
    if ((framebuffer = IOFramebufferPortFromCGDisplayID(displayID))) {
        IOItemCount busCount;
        if (IOFBGetI2CInterfaceCount(framebuffer, &busCount) == KERN_SUCCESS) {
            IOOptionBits bus = 0;
            while (bus < busCount) {
                io_service_t interface;
                if (IOFBCopyI2CInterfaceForBus(framebuffer, bus++, &interface) != KERN_SUCCESS)
                    continue;

                IOI2CConnectRef connect;
                if (IOI2CInterfaceOpen(interface, kNilOptions, &connect) == KERN_SUCCESS) {
                    result = (IOI2CSendRequest(connect, kNilOptions, request) == KERN_SUCCESS);
                    IOI2CInterfaceClose(connect, kNilOptions);
                }
                IOObjectRelease(interface);
                if (result) break;
            }
        }
        IOObjectRelease(framebuffer);
    }
    if (request->replyTransactionType == kIOI2CNoTransactionType)
        usleep(20000);
    dispatch_semaphore_signal(queue);
    return result && request->result == KERN_SUCCESS;
}

bool DDCWrite(CGDirectDisplayID displayID, struct DDCWriteCommand *write) {
    IOI2CRequest    request;
    UInt8           data[128];

    bzero( &request, sizeof(request));

    request.commFlags                       = 0;

    request.sendAddress                     = 0x6E;
    request.sendTransactionType             = kIOI2CSimpleTransactionType;
    request.sendBuffer                      = (vm_address_t) &data[0];
    request.sendBytes                       = 7;

    data[0] = 0x51;
    data[1] = 0x84;
    data[2] = 0x03;
    data[3] = write->control_id;
    data[4] = (write->new_value) >> 8;
    data[5] = write->new_value & 255;
    data[6] = 0x6E ^ data[0] ^ data[1] ^ data[2] ^ data[3]^ data[4] ^ data[5];

    request.replyTransactionType            = kIOI2CNoTransactionType;
    request.replyBytes                      = 0;

    bool result = DisplayRequest(displayID, &request);
    return result;
}

bool DDCRead(CGDirectDisplayID displayID, struct DDCReadCommand *read) {
    IOI2CRequest request;
    UInt8 reply_data[11] = {};
    bool result = false;
    UInt8 data[128];

    for (int i=1; i<=kMaxRequests; i++) {
        bzero(&request, sizeof(request));

        request.commFlags                       = 0;
        request.sendAddress                     = 0x6E;
        request.sendTransactionType             = kIOI2CSimpleTransactionType;
        request.sendBuffer                      = (vm_address_t) &data[0];
        request.sendBytes                       = 5;
        request.minReplyDelay                   = 10;  // too short can freeze kernel

        data[0] = 0x51;
        data[1] = 0x82;
        data[2] = 0x01;
        data[3] = read->control_id;
        data[4] = 0x6E ^ data[0] ^ data[1] ^ data[2] ^ data[3];
#ifdef TT_SIMPLE
        request.replyTransactionType    = kIOI2CSimpleTransactionType;
#elif defined TT_DDC
        request.replyTransactionType    = kIOI2CDDCciReplyTransactionType;
#else
        request.replyTransactionType    = SupportedTransactionType();
#endif
        request.replyAddress            = 0x6F;
        request.replySubAddress         = 0x51;

        request.replyBuffer = (vm_address_t) reply_data;
        request.replyBytes = sizeof(reply_data);

        result = DisplayRequest(displayID, &request);
        result = (result && reply_data[0] == request.sendAddress && reply_data[2] == 0x2 && reply_data[4] == read->control_id && reply_data[10] == (request.replyAddress ^ request.replySubAddress ^ reply_data[1] ^ reply_data[2] ^ reply_data[3] ^ reply_data[4] ^ reply_data[5] ^ reply_data[6] ^ reply_data[7] ^ reply_data[8] ^ reply_data[9]));

        if (result) { // checksum is ok
            if (i > 1) {
                printf("D: Tries required to get data: %d \n", i);
            }
            break;
        }

        if (request.result == kIOReturnUnsupportedMode)
            printf("E: Unsupported Transaction Type! \n");

        // reset values and return 0, if data reading fails
        if (i >= kMaxRequests) {
            read->success = false;
            read->max_value = 0;
            read->current_value = 0;
            printf("E: No data after %d tries! \n", i);
            return 0;
        }

        usleep(40000); // 40msec -> See DDC/CI Vesa Standard - 4.4.1 Communication Error Recovery
    }
    read->success = true;
    read->max_value = reply_data[7];
    read->current_value = reply_data[9];
    return result;
}

UInt32 SupportedTransactionType() {
   /*
     With my setup (Intel HD4600 via displaylink to 'DELL U2515H') the original app failed to read ddc and freezes my system.
     This happens because AppleIntelFramebuffer do not support kIOI2CDDCciReplyTransactionType.
     So this version comes with a reworked ddc read function to detect the correct TransactionType.
     --SamanVDR 2016
   */

    kern_return_t   kr;
    io_iterator_t   io_objects;
    io_service_t    io_service;

    kr = IOServiceGetMatchingServices(kIOMasterPortDefault,
                                      IOServiceNameMatching("IOFramebufferI2CInterface"), &io_objects);

    if (kr != KERN_SUCCESS) {
        printf("E: Fatal - No matching service! \n");
        return 0;
    }

    UInt32 supportedType = 0;

    while((io_service = IOIteratorNext(io_objects)) != MACH_PORT_NULL)
    {
        CFMutableDictionaryRef service_properties;
        CFIndex types = 0;
        CFNumberRef typesRef;

        kr = IORegistryEntryCreateCFProperties(io_service, &service_properties, kCFAllocatorDefault, kNilOptions);
        if (kr == KERN_SUCCESS)
        {
            if (CFDictionaryGetValueIfPresent(service_properties, CFSTR(kIOI2CTransactionTypesKey), (const void**)&typesRef))
                CFNumberGetValue(typesRef, kCFNumberCFIndexType, &types);

            /*
             We want DDCciReply but Simple is better than No-thing.
             Combined and DisplayPortNative are not useful in our case.
             */
            if (types) {
#ifdef DEBUG
                printf("\nD: IOI2CTransactionTypes: 0x%02lx (%ld)\n", types, types);

                // kIOI2CNoTransactionType = 0
                if ( 0 == ((1 << kIOI2CNoTransactionType) & (UInt64)types)) {
                    printf("E: IOI2CNoTransactionType                   unsupported \n");
                } else {
                    printf("D: IOI2CNoTransactionType                   supported \n");
                    supportedType = kIOI2CNoTransactionType;
                }

                // kIOI2CSimpleTransactionType = 1
                if ( 0 == ((1 << kIOI2CSimpleTransactionType) & (UInt64)types)) {
                    printf("E: IOI2CSimpleTransactionType               unsupported \n");
                } else {
                    printf("D: IOI2CSimpleTransactionType               supported \n");
                    supportedType = kIOI2CSimpleTransactionType;
                }

                // kIOI2CDDCciReplyTransactionType = 2
                if ( 0 == ((1 << kIOI2CDDCciReplyTransactionType) & (UInt64)types)) {
                    printf("E: IOI2CDDCciReplyTransactionType           unsupported \n");
                } else {
                    printf("D: IOI2CDDCciReplyTransactionType           supported \n");
                    supportedType = kIOI2CDDCciReplyTransactionType;
                }

                // kIOI2CCombinedTransactionType = 3
                if ( 0 == ((1 << kIOI2CCombinedTransactionType) & (UInt64)types)) {
                    printf("E: IOI2CCombinedTransactionType             unsupported \n");
                } else {
                    printf("D: IOI2CCombinedTransactionType             supported \n");
                    //supportedType = kIOI2CCombinedTransactionType;
                }

                // kIOI2CDisplayPortNativeTransactionType = 4
                if ( 0 == ((1 << kIOI2CDisplayPortNativeTransactionType) & (UInt64)types)) {
                    printf("E: IOI2CDisplayPortNativeTransactionType    unsupported\n");
                } else {
                    printf("D: IOI2CDisplayPortNativeTransactionType    supported \n");
                    //supportedType = kIOI2CDisplayPortNativeTransactionType;
                    // http://hackipedia.org/Hardware/video/connectors/DisplayPort/VESA%20DisplayPort%20Standard%20v1.1a.pdf
                    // http://www.electronic-products-design.com/geek-area/displays/display-port
                }
#else
                // kIOI2CSimpleTransactionType = 1
                if ( 0 != ((1 << kIOI2CSimpleTransactionType) & (UInt64)types)) {
                    supportedType = kIOI2CSimpleTransactionType;
                }

                // kIOI2CDDCciReplyTransactionType = 2
                if ( 0 != ((1 << kIOI2CDDCciReplyTransactionType) & (UInt64)types)) {
                    supportedType = kIOI2CDDCciReplyTransactionType;
                }
#endif
            } else printf("E: Fatal - No supported Transaction Types! \n");

            CFRelease(service_properties);
        }

        IOObjectRelease(io_service);

        // Mac OS offers three framebuffer devices, but we can leave here
        if (supportedType > 0) return supportedType;
    }

    return supportedType;
}


bool EDIDTest(CGDirectDisplayID displayID, struct EDID *edid) {
    IOI2CRequest request = {};
/*! from https://opensource.apple.com/source/IOGraphics/IOGraphics-513.1/IOGraphicsFamily/IOKit/i2c/IOI2CInterface.h.auto.html
 *  not in https://developer.apple.com/reference/kernel/1659924-ioi2cinterface.h/ioi2crequest?changes=latest_beta&language=objc
 * @struct IOI2CRequest
 * @abstract A structure defining an I2C bus transaction.
 * @discussion This structure is used to request an I2C transaction consisting of a send (write) to and reply (read) from a device, either of which is optional, to be carried out atomically on an I2C bus.
 * @field __reservedA Set to zero.
 * @field result The result of the transaction. Common errors are kIOReturnNoDevice if there is no device responding at the given address, kIOReturnUnsupportedMode if the type of transaction is unsupported on the requested bus.
 * @field completion A completion routine to be executed when the request completes. If NULL is passed, the request is synchronous, otherwise it may execute asynchronously.
 * @field commFlags Flags that modify the I2C transaction type. The following flags are defined:<br>
 *      kIOI2CUseSubAddressCommFlag Transaction includes a subaddress.<br>
 * @field minReplyDelay Minimum delay as absolute time between send and reply transactions.
 * @field sendAddress I2C address to write.
 * @field sendSubAddress I2C subaddress to write.
 * @field __reservedB Set to zero.
 * @field sendTransactionType The following types of transaction are defined for the send part of the request:<br>
 *      kIOI2CNoTransactionType No send transaction to perform. <br>
 *      kIOI2CSimpleTransactionType Simple I2C message. <br>
 *      kIOI2CCombinedTransactionType Combined format I2C R/~W transaction. <br>
 * @field sendBuffer Pointer to the send buffer.
 * @field sendBytes Number of bytes to send. Set to actual bytes sent on completion of the request.
 * @field replyAddress I2C Address from which to read.
 * @field replySubAddress I2C Address from which to read.
 * @field __reservedC Set to zero.
 * @field replyTransactionType The following types of transaction are defined for the reply part of the request:<br>
 *      kIOI2CNoTransactionType No reply transaction to perform. <br>
 *      kIOI2CSimpleTransactionType Simple I2C message. <br>
 *      kIOI2CDDCciReplyTransactionType DDC/ci message (with embedded length). See VESA DDC/ci specification. <br>
 *      kIOI2CCombinedTransactionType Combined format I2C R/~W transaction. <br>
 * @field replyBuffer Pointer to the reply buffer.
 * @field replyBytes Max bytes to reply (size of replyBuffer). Set to actual bytes received on completion of the request.
 * @field __reservedD Set to zero.
 */

    UInt8 data[128] = {};
    request.sendAddress = 0xA0;
    request.sendTransactionType = kIOI2CSimpleTransactionType;
    request.sendBuffer = (vm_address_t) data;
    request.sendBytes = 0x01;
    data[0] = 0x00;
    request.replyAddress = 0xA1;
    request.replyTransactionType = kIOI2CSimpleTransactionType;
    request.replyBuffer = (vm_address_t) data;
    request.replyBytes = sizeof(data);
    if (!DisplayRequest(displayID, &request)) return false;
    if (edid) memcpy(edid, &data, 128);
    UInt32 i = 0;
    UInt8 sum = 0;
    while (i < request.replyBytes) {
        if (i % 128 == 0) {
            if (sum) break;
            sum = 0;
        }
        sum += data[i++];
    }
    return !sum;
}
