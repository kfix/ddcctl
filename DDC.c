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
#define kDelayBase 100

static io_service_t IOServicePortFromCGDisplayID(CGDirectDisplayID displayID)
// iterate IOreg to find service port that corresponds to given CGDisplayID
{
    io_iterator_t iter;
    io_service_t serv, servicePort = 0;

    kern_return_t err = IOServiceGetMatchingServices( kIOMasterPortDefault,
                        IOServiceMatching(IOFRAMEBUFFER_CONFORMSTO), // IOFramebufferI2CInterface
                        &iter);

    //if (err != kIOReturnSuccess)
    if (err) // != KERN_SUCCESS)
        return 0;

    while ((serv = IOIteratorNext(iter)))
    {
        CFDictionaryRef info;
        io_name_t	name;
        CFIndex vendorID, productID, serialNumber = 0;
        CFNumberRef vendorIDRef, productIDRef, serialNumberRef;
        CFArrayRef i2cIntsRef;
        CFStringRef location = CFSTR("");
        //CFStringRef serial = CFSTR("");
        Boolean success;

        IORegistryEntryGetName( serv, name );
        // get metadata from IOreg node
        info = IODisplayCreateInfoDictionary(serv, kIODisplayOnlyPreferredName);

/* When assigning a display ID, Quartz considers the following parameters:Vendor, Model, Serial Number and Position in the I/O Kit registry */
        //vendorIDRef = CFDictionaryGetValue(info, CFSTR(kDisplayVendorID));
        //productIDRef = CFDictionaryGetValue(info, CFSTR(kDisplayProductID));
        //serialNumberRef = CFDictionaryGetValue(info, CFSTR(kDisplaySerialNumber));
        CFStringRef locationRef = CFDictionaryGetValue(info, CFSTR(kIODisplayLocationKey));
        location = CFStringCreateCopy(NULL, locationRef);
        //CFStringRef serialRef = CFDictionaryGetValue(info, CFSTR(kDisplaySerialString));
        //serial = CFStringCreateCopy(NULL, serialRef);
        // kDisplayBundleKey
        // kAppleDisplayTypeKey -- if this is an Apple display, can use IODisplay func to change brightness: http://stackoverflow.com/a/32691700/3878712
// http://opensource.apple.com//source/IOGraphics/IOGraphics-179.2/IOGraphicsFamily/IOKit/graphics/IOGraphicsTypes.h

        if(CFDictionaryGetValueIfPresent(info, CFSTR(kDisplayVendorID), (const void**)&vendorIDRef))
	        success = CFNumberGetValue(vendorIDRef, kCFNumberCFIndexType, &vendorID);

        if(CFDictionaryGetValueIfPresent(info, CFSTR(kDisplayProductID), (const void**)&productIDRef))
        	success &= CFNumberGetValue(productIDRef, kCFNumberCFIndexType, &productID);

        IOItemCount busCount;
        IOFBGetI2CInterfaceCount(serv, &busCount);

        if (!success || busCount < 1)
        {
            CFRelease(info);
            continue;
        } 
        //else 
           // "IOFBI2CInterfaceInfo" = ({"IOI2CBusType"=1  // MacBook screens do not have a BusType

        if(CFDictionaryGetValueIfPresent(info, CFSTR(kDisplaySerialNumber), (const void**)&serialNumberRef))
        {
             CFNumberGetValue(serialNumberRef, kCFNumberCFIndexType, &serialNumber);
        }
        // compare IOreg's metadata to CGDisplay's metadata to infer if the IOReg's I2C monitor is the display for the given NSScreen.displayID
        /* The logical unit number represents a particular node in the I/O Kit device tree associated with the display’s framebuffer.
For a particular hardware configuration, this value will not change when the attached monitor is changed. The number will change, though, if the I/O Kit device tree changes, for example, when hardware is reconfigured, drivers are replaced, or significant changes occur to I/O Kit. Therefore keep in mind that this number may vary across login sessions. */
// ^ so unitnumber follows NSSpace>framebuffer>GPU and not actual monitors :-(
        if (CGDisplayVendorNumber(displayID) != vendorID ||
            CGDisplayModelNumber(displayID) != productID ||
            CGDisplaySerialNumber(displayID) != serialNumber ) // is zero in lots of cases, so duplicate-monitor rigs can get confused :-/
            // || compare CGDisplayUnitNumber to IO location/iternum?
        {
            CFRelease(info);
            continue;
        }

        // we're a match
        printf("VN:%ld PN:%ld SN:%ld", vendorID, productID, serialNumber);
        printf(" UN:%d", CGDisplayUnitNumber(displayID));
        //printf(" Serial:%s\n", CFStringGetCStringPtr(serial, kCFStringEncodingUTF8));
        printf(" %s %s\n", name, CFStringGetCStringPtr(location, kCFStringEncodingUTF8));
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
    //if ((framebuffer = CGDisplayIOServicePort(displayID))) {
    // DEPRECATED! https://developer.apple.com/library/mac/documentation/GraphicsImaging/Reference/Quartz_Services_Ref/index.html#//apple_ref/c/func/CGDisplayIOServicePort
    // http://stackoverflow.com/questions/20025868/cgdisplayioserviceport-is-deprecated-in-os-x-10-9-how-to-replace
    // http://stackoverflow.com/questions/24348142/cgdirectdisplayid-multiple-gpus-deprecated-cgdisplayioserviceport-and-uniquely
    if ((framebuffer = IOServicePortFromCGDisplayID(displayID))) { // https://github.com/glfw/glfw/pull/192/files
        IOItemCount busCount;
        if (IOFBGetI2CInterfaceCount(framebuffer, &busCount) == KERN_SUCCESS) {
            // https://developer.apple.com/library/mac/documentation/IOKit/Reference/IOI2CInterface_iokit_header_reference/#//apple_ref/c/func/IOFBGetI2CInterfaceCount
            IOOptionBits bus = 0;
            while (bus < busCount) {
                io_service_t interface;
                if (IOFBCopyI2CInterfaceForBus(framebuffer, bus++, &interface) != KERN_SUCCESS)
                    continue;
                CFNumberRef flags = NULL;
                CFIndex flag;
                if (request->minReplyDelay
                    && (flags = IORegistryEntryCreateCFProperty(interface, CFSTR(kIOI2CSupportedCommFlagsKey), kCFAllocatorDefault, 0))
                    && CFNumberGetValue(flags, kCFNumberCFIndexType, &flag)
                    && flag == kIOI2CUseSubAddressCommFlag)
                    request->minReplyDelay *= kMillisecondScale;
                if (flags)
                    CFRelease(flags);
                IOI2CConnectRef connect;
                if (IOI2CInterfaceOpen(interface, kNilOptions, &connect) == KERN_SUCCESS) {
                    result = (IOI2CSendRequest(connect, kNilOptions, request) == KERN_SUCCESS);
                    IOI2CInterfaceClose(connect, kNilOptions);
                }
                IOObjectRelease(interface);
                if (result) break;
            }
        }
    }
    if (request->replyTransactionType == kIOI2CNoTransactionType)
        usleep(kDelayBase * kMicrosecondScale);
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


    request.replyTransactionType    = kIOI2CNoTransactionType;
    request.replyBytes                      = 0;


    bool result = DisplayRequest(displayID, &request);
    return result;
}

bool DDCRead(CGDirectDisplayID displayID, struct DDCReadCommand *read) {
    IOI2CRequest request;
    UInt8 reply_data[11] = {};
    bool result = false;
    UInt8 data[128];


    bzero( &request, sizeof(request));

    request.commFlags                       = 0;

    request.sendAddress                     = 0x6E;
    request.sendTransactionType             = kIOI2CSimpleTransactionType;
    request.sendBuffer                      = (vm_address_t) &data[0];
    request.sendBytes                       = 5;
    request.minReplyDelay                   = kDelayBase;

    data[0] = 0x51;
    data[1] = 0x82;
    data[2] = 0x01;
    data[3] = read->control_id;
    data[4] = 0x6E ^ data[0] ^ data[1] ^ data[2] ^ data[3];

    request.replyTransactionType    = kIOI2CDDCciReplyTransactionType;
    request.replyAddress            = 0x6F;
    request.replySubAddress         = 0x51;

    request.replyBuffer = (vm_address_t) reply_data;
    request.replyBytes = sizeof(reply_data);

    result = DisplayRequest(displayID, &request);
    result = (result && reply_data[0] == request.sendAddress && reply_data[2] == 0x2 && reply_data[4] == read->control_id && reply_data[10] == (request.replyAddress ^ request.replySubAddress ^ reply_data[1] ^ reply_data[2] ^ reply_data[3] ^ reply_data[4] ^ reply_data[5] ^ reply_data[6] ^ reply_data[7] ^ reply_data[8] ^ reply_data[9]));
    read->max_value = reply_data[7];
    read->current_value = reply_data[9];
    return result;
}

bool EDIDTest(CGDirectDisplayID displayID, struct EDID *edid) {
    IOI2CRequest request = {};
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
