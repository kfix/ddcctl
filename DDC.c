//
//  DDC.c
//  DDC Panel
//
//  Created by Jonathan Taylor on 7/10/09.
//  See http://github.com/jontaylor/DDC-CI-Tools-for-OS-X
//


#include <IOKit/IOKitLib.h>
#include <ApplicationServices/ApplicationServices.h>
#include "DDC.h"
#define kDelayBase 60

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
    io_service_t framebuffer;
    if ((framebuffer = CGDisplayIOServicePort(displayID))) {
        IOItemCount busCount;
        if (IOFBGetI2CInterfaceCount(framebuffer, &busCount) == KERN_SUCCESS) {
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
    IOI2CRequest request = {};
    request.commFlags = kIOI2CUseSubAddressCommFlag;
    request.sendAddress = 0x6E;
    request.sendSubAddress = 0x51;
    request.sendTransactionType = kIOI2CSimpleTransactionType;
    UInt8 data[6] = {0x80, 0x03, write->control_id, 0x0, write->new_value};
    data[0]+=sizeof(data)-2;
    data[5] = request.sendAddress ^ request.sendSubAddress ^ data[0] ^ data[1] ^ data[2] ^ data[3] ^ data[4];
    request.sendBuffer = (vm_address_t) data;
    request.sendBytes = sizeof(data);
    request.replyTransactionType = kIOI2CNoTransactionType;
    bool result = DisplayRequest(displayID, &request);
    return result;
}
bool DDCRead(CGDirectDisplayID displayID, struct DDCReadCommand *read) {
    IOI2CRequest request = {};
    UInt8 reply_data[11] = {};
    bool result = false;
    request.commFlags = kIOI2CUseSubAddressCommFlag;
    request.sendAddress = 0x6E;
    request.sendSubAddress = 0x51;
    request.sendTransactionType = kIOI2CSimpleTransactionType;
    UInt8 data[4] = {0x80, 0x1, read->control_id};
    data[0]+=sizeof(data)-2;
    data[3] = request.sendAddress ^ request.sendSubAddress ^ data[0] ^ data[1] ^ data[2];
    request.sendBuffer = (vm_address_t) data;
    request.sendBytes = sizeof(data);
    request.replyAddress = 0x6F;
    request.replySubAddress = request.sendSubAddress;
    request.replyTransactionType = kIOI2CDDCciReplyTransactionType;
    request.replyBuffer = (vm_address_t) reply_data;
    request.replyBytes = sizeof(reply_data);
    request.minReplyDelay = kDelayBase;
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