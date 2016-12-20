//
//  ddcctl.m
//  query and control monitors through their on-wire data channels and OSD microcontrollers
//  http://en.wikipedia.org/wiki/Display_Data_Channel#DDC.2FCI
//  http://en.wikipedia.org/wiki/Monitor_Control_Command_Set
//
//  Copyright Joey Korkames 2014 http://github.com/kfix
//  Licensed under GPLv3, full text at http://www.gnu.org/licenses/gpl-3.0.txt
//

//
//  Marc (Saman-VDR) 2016:
//  With my setup (Intel HD4600 via displaylink to 'DELL U2515H') the original app failed to read ddc and freezes my system.
//  This happens because AppleIntelFramebuffer do not support kIOI2CDDCciReplyTransactionType.
//  So this version comes with a reworked ddc read function to detect the correct TransactionType.
//  Kernel freezes were fixed by setting minReplyDelay to 10
//  Now reading data from my DELL is possible!
//
//
//  New command-line keys for testing (working with my DELL):
//  -rg 1-100  -> red gain
//  -gg 1-100  -> green gain
//  -bg 1-100  -> blue gain
//  -rrgb      -> reset color
//  -rbc       -> reset brightness and contrast
//
//
//  Now using argv[] instead off user-defaults to handle commandline arguments.
//
//  Added optional use of an external app 'OSDisplay' to have a BezelUI like OSD.
//  Edit Makefile to define OSD, then recompile. Use '-O' as a command to activate.
//
//  Have fun!
//

#ifdef DEBUG
#define MyLog NSLog
#else
#define MyLog(...) (void)printf("%s\n",[[NSString stringWithFormat:__VA_ARGS__] UTF8String])
#endif

#import <Foundation/Foundation.h>
#import <AppKit/NSScreen.h>
#import "DDC.h"

#ifdef BLACKLIST
NSUserDefaults *defaults;
int blacklistedDeviceWithNumber;
#endif
#ifdef OSD
bool useOsd;
#endif


NSString *EDIDString(char *string)
{
    NSString *temp = [[NSString alloc] initWithBytes:string length:13 encoding:NSASCIIStringEncoding];
    return ([temp rangeOfString:@"\n"].location != NSNotFound) ? [[temp componentsSeparatedByString:@"\n"] objectAtIndex:0] : temp;
}

/* Get current value for control from display */
uint getControl(CGDirectDisplayID cdisplay, uint control_id)
{
    struct DDCReadCommand command;
    command.control_id = control_id;
    command.max_value = 0;
    command.current_value = 0;
    MyLog(@"D: querying VCP control: #%u =?", command.control_id);
    
    if (!DDCRead(cdisplay, &command)) {
        MyLog(@"E: DDC send command failed!");
        MyLog(@"E: VCP control #%u (0x%02hhx) = current: %u, max: %u", command.control_id, command.control_id, command.current_value, command.max_value);
    } else {
        MyLog(@"I: VCP control #%u (0x%02hhx) = current: %u, max: %u", command.control_id, command.control_id, command.current_value, command.max_value);
    }
    return command.current_value;
}

/* Set new value for control from display */
void setControl(CGDirectDisplayID cdisplay, uint control_id, uint new_value)
{
    struct DDCWriteCommand command;
    command.control_id = control_id;
    command.new_value = new_value;
    
    MyLog(@"D: setting VCP control #%u => %u", command.control_id, command.new_value);
    if (!DDCWrite(cdisplay, &command)){
        MyLog(@"E: Failed to send DDC command!");
    }
#ifdef OSD
    if (useOsd) {
        NSString *OSDisplay = @"/Applications/OSDisplay.app/Contents/MacOS/OSDisplay";
        switch (control_id) {
            case 16:
                [NSTask launchedTaskWithLaunchPath:OSDisplay
                                         arguments:[NSArray arrayWithObjects:
                                                    @"-l", [NSString stringWithFormat:@"%u", new_value],
                                                    @"-i", @"brightness", nil]];
                break;
                
            case 18:
                [NSTask launchedTaskWithLaunchPath:OSDisplay
                                         arguments:[NSArray arrayWithObjects:
                                                    @"-l", [NSString stringWithFormat:@"%u", new_value],
                                                    @"-i", @"contrast", nil]];
                break;
                
            default:
                break;
        }
    }
#endif
}

/* Get current value to Set relative value for control from display */
void getSetControl(CGDirectDisplayID cdisplay, uint control_id, NSString *new_value, NSString *operator)
{
    struct DDCReadCommand command;
    command.control_id = control_id;
    command.max_value = 0;
    command.current_value = 0;
    
    // read
    MyLog(@"D: querying VCP control: #%u =?", command.control_id);
    
    if (!DDCRead(cdisplay, &command)) {
        MyLog(@"E: DDC send command failed!");
        MyLog(@"E: VCP control #%u (0x%02hhx) = current: %u, max: %u", command.control_id, command.control_id, command.current_value, command.max_value);
    } else {
        MyLog(@"I: VCP control #%u (0x%02hhx) = current: %u, max: %u", command.control_id, command.control_id, command.current_value, command.max_value);
    }
    
    // calculate
    NSString *formula = [NSString stringWithFormat:@"%u %@ %@", command.current_value, operator, new_value];
    NSExpression *exp = [NSExpression expressionWithFormat:formula];
    NSNumber *set_value = [exp expressionValueWithObject:nil context:nil];

    // validate and write
    if (set_value.intValue >= 0 && set_value.intValue <= command.max_value) {
        MyLog(@"D: relative setting: %@ = %d", formula, set_value.intValue);
        setControl(cdisplay, control_id, set_value.unsignedIntValue);
    } else {
        MyLog(@"D: relative setting: %@ = %d is out of range!", formula, set_value.intValue);
    }
}

/* Main function */
int main(int argc, const char * argv[])
{
    
    @autoreleasepool {
        
        NSPointerArray *_displayIDs = [NSPointerArray pointerArrayWithOptions:NSPointerFunctionsOpaqueMemory | NSPointerFunctionsIntegerPersonality];
        
        for (NSScreen *screen in NSScreen.screens)
        {
            NSDictionary *description = [screen deviceDescription];
            if ([description objectForKey:@"NSDeviceIsScreen"]) {
                CGDirectDisplayID screenNumber = [[description objectForKey:@"NSScreenNumber"] unsignedIntValue];
                [_displayIDs addPointer:(void *)(UInt64)screenNumber];
                NSSize displayPixelSize = [[description objectForKey:NSDeviceSize] sizeValue];
                CGSize displayPhysicalSize = CGDisplayScreenSize(screenNumber); // dspPhySz only valid if EDID present!
                float displayScale = [screen backingScaleFactor];
                if (displayScale > 1) {
                    MyLog(@"D: NSScreen #%u (%.0fx%.0f HiDPI)",
                          screenNumber,
                          displayPixelSize.width,
                          displayPixelSize.height);
                }
                else {
                    MyLog(@"D: NSScreen #%u (%.0fx%.0f) DPI is %0.2f",
                          screenNumber,
                          displayPixelSize.width,
                          displayPixelSize.height,
                          (displayPixelSize.width / displayPhysicalSize.width) * 25.4f); // there being 25.4 mm in an inch
                }
            }
        }
        MyLog(@"I: found %lu display%@", [_displayIDs count], [_displayIDs count] > 1 ? @"s" : @"");

        
        // Defaults
        NSString *screenName = @"";
        NSUInteger displayId = -1;
        NSUInteger command_interval = 100000;
        BOOL dump_values = NO;
        
        NSString *HelpString = @"Usage:\n"
        @"ddcctl \t-d <1-..>  [display#]\n"
        @"\t-w 100000  [delay usecs between settings]\n"
        @"\n"
        @"----- Basic settings -----\n"
        @"\t-b <1-..>  [brightness]\n"
        @"\t-c <1-..>  [contrast]\n"
        @"\t-rbc       [reset brightness and contrast]\n"
#ifdef OSD
        @"\t-O         [osd: needs external app 'OSDisplay']\n"
#endif
        @"\n"
        @"----- Settings that don\'t always work -----\n"
        @"\t-m <1|2>   [mute speaker OFF/ON]\n"
        @"\t-v <1-254> [speaker volume]\n"
        @"\t-i <1-12>  [select input source]\n"
        @"\t-p <1|2-5> [power on | standby/off]\n"
        @"\t-o         [read-only orientation]\n"
        @"\n"
        @"----- Settings (testing) -----\n"
        @"\t-rg <1-..>  [red gain]\n"
        @"\t-gg <1-..>  [green gain]\n"
        @"\t-bg <1-..>  [blue gain]\n"
        @"\t-rrbg       [reset color]\n"
        @"\n"
        @"----- Setting grammar -----\n"
        @"\t-X ?       (query value of setting X)\n"
        @"\t-X NN      (put setting X to NN)\n"
        @"\t-X <NN>-   (decrease setting X by NN)\n"
        @"\t-X <NN>+   (increase setting X by NN)";
        
        
        // Commandline Arguments
        NSMutableDictionary *actions = [[NSMutableDictionary alloc] init];
        
        for (int i=1; i<argc; i++)
        {
            if (!strcmp(argv[i], "-d")) {
                i++;
                if (i >= argc) break;
                displayId = atoi(argv[i]);
            }
            
            else if (!strcmp(argv[i], "-b")) {
                i++;
                if (i >= argc) break;
                [actions setObject:@[@BRIGHTNESS, [[NSString alloc] initWithUTF8String:argv[i]]] forKey:@"b"];
            }
            
            else if (!strcmp(argv[i], "-c")) {
                i++;
                if (i >= argc) break;
                [actions setObject:@[@CONTRAST, [[NSString alloc] initWithUTF8String:argv[i]]] forKey:@"c"];
            }
            
            else if (!strcmp(argv[i], "-rbc")) {
                [actions setObject:@[@RESET_BRIGHTNESS_AND_CONTRAST, @"1"] forKey:@"rbc"];
            }
            
            else if (!strcmp(argv[i], "-rg")) {
                i++;
                if (i >= argc) break;
                [actions setObject:@[@RED_GAIN, [[NSString alloc] initWithUTF8String:argv[i]]] forKey:@"rg"];
            }
            
            else if (!strcmp(argv[i], "-gg")) {
                i++;
                if (i >= argc) break;
                [actions setObject:@[@GREEN_GAIN, [[NSString alloc] initWithUTF8String:argv[i]]] forKey:@"gg"];
            }
            
            else if (!strcmp(argv[i], "-bg")) {
                i++;
                if (i >= argc) break;
                [actions setObject:@[@BLUE_GAIN, [[NSString alloc] initWithUTF8String:argv[i]]] forKey:@"bg"];
            }
            
            else if (!strcmp(argv[i], "-rrgb")) {
                [actions setObject:@[@RESET_COLOR, @"1"] forKey:@"rrgb"];
            }
            
            else if (!strcmp(argv[i], "-D")) {
                dump_values = YES;
            }

            else if (!strcmp(argv[i], "-p")) {
                i++;
                if (i >= argc) break;
                [actions setObject:@[@DPMS, [[NSString alloc] initWithUTF8String:argv[i]]] forKey:@"p"];
            }
            
            else if (!strcmp(argv[i], "-o")) { // read only
                [actions setObject:@[@ORIENTATION, @"?"] forKey:@"o"];
            }
            
            else if (!strcmp(argv[i], "-osd")) { // read only - returns '1' (OSD closed) or '2' (OSD active)
                [actions setObject:@[@ON_SCREEN_DISPLAY, @"?"] forKey:@"osd"];
            }
            
            else if (!strcmp(argv[i], "-lang")) { // read only
                [actions setObject:@[@OSD_LANGUAGE, @"?"] forKey:@"lang"];
            }
            
            else if (!strcmp(argv[i], "-reset")) {
                [actions setObject:@[@RESET, @"1"] forKey:@"reset"];
            }
            
            else if (!strcmp(argv[i], "-preset_a")) {
                i++;
                if (i >= argc) break;
                [actions setObject:@[@COLOR_PRESET_A, [[NSString alloc] initWithUTF8String:argv[i]]] forKey:@"preset_a"];
            }
            
            else if (!strcmp(argv[i], "-preset_b")) {
                i++;
                if (i >= argc) break;
                [actions setObject:@[@COLOR_PRESET_B, [[NSString alloc] initWithUTF8String:argv[i]]] forKey:@"preset_b"];
            }
            
            else if (!strcmp(argv[i], "-preset_c")) {
                i++;
                if (i >= argc) break;
                [actions setObject:@[@COLOR_PRESET_C, [[NSString alloc] initWithUTF8String:argv[i]]] forKey:@"preset_c"];
            }
            
            else if (!strcmp(argv[i], "-i")) {
                i++;
                if (i >= argc) break;
                [actions setObject:@[@INPUT_SOURCE, [[NSString alloc] initWithUTF8String:argv[i]]] forKey:@"i"];
            }
            
            else if (!strcmp(argv[i], "-m")) {
                i++;
                if (i >= argc) break;
                [actions setObject:@[@AUDIO_MUTE, [[NSString alloc] initWithUTF8String:argv[i]]] forKey:@"m"];
            }
            
            else if (!strcmp(argv[i], "-v")) {
                i++;
                if (i >= argc) break;
                [actions setObject:@[@AUDIO_SPEAKER_VOLUME, [[NSString alloc] initWithUTF8String:argv[i]]] forKey:@"v"];
            }
            
            else if (!strcmp(argv[i], "-w")) {
                i++;
                if (i >= argc) break;
                command_interval = atoi(argv[i]);
            }
#ifdef OSD
            else if (!strcmp(argv[i], "-O")) {
                useOsd = YES;
            }
#endif
#ifdef TEST
            else if (!strcmp(argv[i], "-test")) {
                i++;
                if (i >= argc) break;
                NSString *test = [[NSString alloc] initWithUTF8String:argv[i]];
                i++;
                if (i >= argc) break;
                [actions setObject:@[test, [[NSString alloc] initWithUTF8String:argv[i]]] forKey:@"test"];
                NSLog(@"TEST: %@  %@", test, [[NSString alloc] initWithUTF8String:argv[i]]);
            }
#endif
            else if (!strcmp(argv[i], "-h")) {
                NSLog(@"ddcctl 0.1x - %@", HelpString);
                return 0;
            }
            
            else {
                NSLog(@"Unknown argument: %@", [[NSString alloc] initWithUTF8String:argv[i]]);
                return -1;
            }
        }
        
        
        // Let's go...
        if (0 < displayId && displayId <= [_displayIDs count]) {
            MyLog(@"I: polling display %lu's EDID", displayId);
            CGDirectDisplayID cdisplay = (CGDirectDisplayID)[_displayIDs pointerAtIndex:displayId - 1];
            struct EDID edid = {};
            if (EDIDTest(cdisplay, &edid)) {
                for (NSValue *value in @[[NSValue valueWithPointer:&edid.descriptor1],
                                         [NSValue valueWithPointer:&edid.descriptor2],
                                         [NSValue valueWithPointer:&edid.descriptor3],
                                         [NSValue valueWithPointer:&edid.descriptor4]])
                {
                    union descriptor *des = value.pointerValue;
                    switch (des->text.type)
                    {
                        case 0xFF:
                            MyLog(@"I: got edid.serial: %@", EDIDString(des->text.data));
                            break;
                        case 0xFC:
                            screenName = EDIDString(des->text.data);
                            MyLog(@"I: got edid.name: %@", screenName);
                            break;
                    }
                }
                
                // Debugging
                if (dump_values) {
                    for (uint i=0x00; i<=255; i++) {
                        getControl(cdisplay, i);
                        usleep(command_interval);
                    }
                }
                
                // Actions
                [actions enumerateKeysAndObjectsUsingBlock:^(id argname, NSArray* valueArray, BOOL *stop) {
                    NSInteger control_id = [valueArray[0] intValue];
                    NSString *argval = valueArray[1];
                    MyLog(@"D: action: %@: %@", argname, argval);
                    
                    if (control_id > -1) {
                        // this is a valid monitor control
                        NSString *argval_num = [argval stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"-+"]]; // look for relative setting ops
                        if (argval != argval_num) {
                            // relative setting: read, calculate, then write
                            getSetControl(cdisplay, control_id, argval_num, [argval substringFromIndex:argval.length - 1]);
                        } else if ([argval hasPrefix:@"?"]) {
                            // read current setting
                            getControl(cdisplay, control_id);
                        } else {
                            // write fixed setting
                            setControl(cdisplay, control_id, [argval intValue]);
                        }
                    }
                    usleep(command_interval); // stagger comms to these wimpy I2C mcu's
                }];
                
            } else {
                MyLog(@"E: Failed to poll display!");
                return -1;
            }
        } else { // no display id given
            NSLog(@"%@", HelpString);
        }
    }
    return 0;
}
