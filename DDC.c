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

#define kMaxRequests 10

static io_service_t IOFramebufferPortFromCGDisplayID(CGDirectDisplayID displayID)
//  iterate IOreg's device tree to find the IOFramebuffer mach service port that corresponds to a given CGDisplayID
//  replaces CGDisplayIOServicePort: https://developer.apple.com/library/mac/documentation/GraphicsImaging/Reference/Quartz_Services_Ref/index.html#//apple_ref/c/func/CGDisplayIOServicePort
//  based on: https://github.com/glfw/glfw/pull/192/files
{
    io_iterator_t iter;
    io_service_t serv, servicePort = 0;
    
    kern_return_t err = IOServiceGetMatchingServices( kIOMasterPortDefault,
                                                     IOServiceMatching(IOFRAMEBUFFER_CONFORMSTO), // IOFramebufferI2CInterface
                                                     &iter);
    
    if (err != KERN_SUCCESS)
        return 0;
    
    // now recurse the IOReg tree
    while ((serv = IOIteratorNext(iter)) != MACH_PORT_NULL)
    {
        CFDictionaryRef info;
        io_name_t	name;
        CFIndex vendorID, productID, serialNumber = 0;
        CFNumberRef vendorIDRef, productIDRef, serialNumberRef;
        CFStringRef location = CFSTR("");
        //CFStringRef serial = CFSTR("");
        Boolean success = 0;
        
        // get metadata from IOreg node
        IORegistryEntryGetName(serv, name);
        info = IODisplayCreateInfoDictionary(serv, kIODisplayOnlyPreferredName);
        
        /* When assigning a display ID, Quartz considers the following parameters:Vendor, Model, Serial Number and Position in the I/O Kit registry */
        // http://opensource.apple.com//source/IOGraphics/IOGraphics-179.2/IOGraphicsFamily/IOKit/graphics/IOGraphicsTypes.h
        CFStringRef locationRef = CFDictionaryGetValue(info, CFSTR(kIODisplayLocationKey));
        location = CFStringCreateCopy(NULL, locationRef);
        //CFStringRef serialRef = CFDictionaryGetValue(info, CFSTR(kDisplaySerialString));
        //serial = CFStringCreateCopy(NULL, serialRef);
        
        if (CFDictionaryGetValueIfPresent(info, CFSTR(kDisplayVendorID), (const void**)&vendorIDRef))
            success = CFNumberGetValue(vendorIDRef, kCFNumberCFIndexType, &vendorID);
        
        if (CFDictionaryGetValueIfPresent(info, CFSTR(kDisplayProductID), (const void**)&productIDRef))
            success &= CFNumberGetValue(productIDRef, kCFNumberCFIndexType, &productID);
        
        IOItemCount busCount;
        IOFBGetI2CInterfaceCount(serv, &busCount);
        
        if (!success || busCount < 1) {
            // this does not seem to be a DDC-enabled display, skip it
            CFRelease(info);
            continue;
        } else {
            // MacBook built-in screens have IOFBI2CInterfaceIDs=(0) but do not respond to DDC comms
            // they also do not have a BusType: IOFBI2CInterfaceInfo = ({"IOI2CBusType"=1 .. })
            // if (framebuffer.hasDDCConnect(0)) // https://developer.apple.com/reference/kernel/ioframebuffer/1813510-hasddcconnect?language=objc
            // kDisplayBundleKey
            // kAppleDisplayTypeKey -- if this is an Apple display, can use IODisplay func to change brightness: http://stackoverflow.com/a/32691700/3878712
        }
        
        if (CFDictionaryGetValueIfPresent(info, CFSTR(kDisplaySerialNumber), (const void**)&serialNumberRef))
            CFNumberGetValue(serialNumberRef, kCFNumberCFIndexType, &serialNumber);
        
        // compare IOreg's metadata to CGDisplay's metadata to infer if the IOReg's I2C monitor is the display for the given NSScreen.displayID
        if (CGDisplayVendorNumber(displayID) != vendorID ||
            CGDisplayModelNumber(displayID) != productID ||
            CGDisplaySerialNumber(displayID) != serialNumber ) // SN is zero in lots of cases, so duplicate-monitors can confuse us :-/
        {
            CFRelease(info);
            continue;
        }
        
        // considering this IOFramebuffer as the match for the CGDisplay, dump out its information
//        printf("VN:%ld PN:%ld SN:%ld", vendorID, productID, serialNumber);
//        printf(" UN:%d", CGDisplayUnitNumber(displayID));
//        printf(" IN:%d", iter);
        //printf(" Serial:%s\n", CFStringGetCStringPtr(serial, kCFStringEncodingUTF8));
//        printf(" %s %s\n", name, CFStringGetCStringPtr(location, kCFStringEncodingUTF8));
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
        queues = calloc(50, sizeof(*queues));//FIXME: specify
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

    for (int i=0; i<kMaxRequests; i++) {
        bzero(&request, sizeof(request));
        
        request.commFlags                       = 0;   
        request.sendAddress                     = 0x6E;
        request.sendTransactionType             = kIOI2CSimpleTransactionType;
        request.sendBuffer                      = (vm_address_t) &data[0];
        request.sendBytes                       = 5;
        request.minReplyDelay                   = 10;  // may differ, but this is working
        
        data[0] = 0x51;
        data[1] = 0x82;
        data[2] = 0x01;
        data[3] = read->control_id;
        data[4] = 0x6E ^ data[0] ^ data[1] ^ data[2] ^ data[3];
        
        //request.replyTransactionType    = kIOI2CDDCciReplyTransactionType;
        request.replyTransactionType    = kIOI2CSimpleTransactionType;
        request.replyAddress            = 0x6F;
        request.replySubAddress         = 0x51;
        
        request.replyBuffer = (vm_address_t) reply_data;
        request.replyBytes = sizeof(reply_data);
        
        result = DisplayRequest(displayID, &request);
        result = (result && reply_data[0] == request.sendAddress && reply_data[2] == 0x2 && reply_data[4] == read->control_id && reply_data[10] == (request.replyAddress ^ request.replySubAddress ^ reply_data[1] ^ reply_data[2] ^ reply_data[3] ^ reply_data[4] ^ reply_data[5] ^ reply_data[6] ^ reply_data[7] ^ reply_data[8] ^ reply_data[9]));
    
        if (result) { // checksum is ok
            if (i >= 1) {
                printf("D: Tries required to get data: %d \n", i+1);
            }
            break;
        }

        if (request.result == kIOReturnUnsupportedMode)
            printf("E: Unsupported Transaction Type! \n");
        
        // reset values and return 0, if data reading fails
        if (i+1 >= kMaxRequests) {
            read->max_value = 0;
            read->current_value = 0;
            printf("E: No data after %d tries! \n", i+1);
            return 0;
        }
        
        usleep(40000); // 40msec -> See DDC/CI Vesa Standard - 4.4.1 Communication Error Recovery
    }
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
