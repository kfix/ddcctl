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
//  With my setup (Intel HD4600 via displaylink to 'DELL U2515H') the app failed to read ddc and freezes my system.
//
//  This is why I added blacklist support:
//  Now the app can use the user-defaults to hold the current brightness and contrast values.
//  The settings were saved to ~/Library/Preferences/ddcctl.plist
//  Here you can add your display by edid.name into the blacklist (needs a reboot).
//  Or just use the '-u y' switch to enable this feature.
//  Display 1, 2 and 3 have predefined values of 50 so 'calibrating' is easy.
//  Simply adjust your display to 50 before you start the app the first time.
//  From there, only use the app to adjust your display and you are fine.
//
//  Tipp: Use 'Karabiner' to map some keyboard keys to 5- and 5+
//  For me this works exelent with the brightness keys of my apple magic keyboard.
//
//  Since I set minReplyDelay to zero, my system didn't freeze any more
//  But my Dell gives me old values at the first read so I add: save-mode
//  In save-mode the app reads current value twice to be sure. Use '-s' to activate.
//
//  Now using argv[] instead off user-defaults to handle commandline arguments.
//
//  Added optional use of an external app 'OSDisplay' to have a BezelUI like OSD.
//  Use '-O' to activate.
//
//  Have fun!
//

//#define OSD

#ifdef DEBUG
#define MyLog NSLog
#else
#define MyLog(...) (void)printf("%s\n",[[NSString stringWithFormat:__VA_ARGS__] UTF8String])
#endif

#import <Foundation/Foundation.h>
#import <AppKit/NSScreen.h>
#import "DDC.h"

NSUserDefaults *defaults;
int blacklistedDeviceWithNumber;
bool useSaveMode;
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
    
    if (blacklistedDeviceWithNumber > 0) {
        MyLog(@"D: reading user-defaults");
        switch (control_id) {
            case 16:
                command.current_value = [defaults integerForKey:[NSString stringWithFormat:@"Brightness-%u", blacklistedDeviceWithNumber]];
                command.max_value = [defaults integerForKey:@"MaxValue"];
                break;
                
            case 18:
                command.current_value = [defaults integerForKey:[NSString stringWithFormat:@"Contrast-%u", blacklistedDeviceWithNumber]];
                command.max_value = [defaults integerForKey:@"MaxValue"];
                break;
                
            default:
                break;
        }
        MyLog(@"I: VCP control #%u = current: %u, max: %u", command.control_id, command.current_value, command.max_value);
        
    } else {
        MyLog(@"D: querying VCP control: #%u =?", command.control_id);
        
        if (useSaveMode) {
            DDCRead(cdisplay, &command);
            usleep(100 * kMicrosecondScale);
        }
        
        if (!DDCRead(cdisplay, &command)) {
            MyLog(@"E: DDC send command failed!");
            MyLog(@"E: VCP control #%u = current: %u, max: %u", command.control_id, command.current_value, command.max_value);
        } else {
            MyLog(@"I: VCP control #%u = current: %u, max: %u", command.control_id, command.current_value, command.max_value);
        }
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
    else if (blacklistedDeviceWithNumber > 0) {
        // DDCWrite success and device was found in blacklist
        // so we save new value for the device number to user-defaults
        switch (control_id) {
            case 16:
                [defaults setInteger:new_value forKey:[NSString stringWithFormat:@"Brightness-%u", blacklistedDeviceWithNumber]];
                break;
                
            case 18:
                [defaults setInteger:new_value forKey:[NSString stringWithFormat:@"Contrast-%u", blacklistedDeviceWithNumber]];
                break;
                
            default:
                break;
        }
        [defaults synchronize];
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
        NSString *useDefaults = @"";
        
        NSString *HelpString = @"Usage:\n"
        @"ddcctl \t-d <1-..>  [display#]\n"
        @"\t-w 100000  [delay usecs between settings]\n"
        @"\n"
        @"----- Basic settings -----\n"
        @"\t-b <1-..>  [brightness]\n"
        @"\t-c <1-..>  [contrast]\n"
        @"\t-u <y|n|c> [blacklist on|off|create]\n"
        @"\t-s         [save-mode: read current value twice to be sure]\n"
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
            
            else if (!strcmp(argv[i], "-D")) {
                dump_values = YES;
            }
            
            else if (!strcmp(argv[i], "-u")) {
                i++;
                if (i >= argc) break;
                useDefaults = [[NSString alloc] initWithUTF8String:argv[i]];
            }
            
            else if (!strcmp(argv[i], "-s")) {
                useSaveMode = YES;
            }
            
            else if (!strcmp(argv[i], "-p")) {
                i++;
                if (i >= argc) break;
                [actions setObject:@[@DPMS, [[NSString alloc] initWithUTF8String:argv[i]]] forKey:@"p"];
            }
            
            else if (!strcmp(argv[i], "-o")) {
                i++;
                if (i >= argc) break;
                //[actions setObject:@[@ORIENTATION, [[NSString alloc] initWithUTF8String:argv[i]]] forKey:@"o"];
                [actions setObject:@[@ORIENTATION, @"?"] forKey:@"o"];
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
            else if (!strcmp(argv[i], "-h")) {
                NSLog(@"ddctl 0.1 - %@", HelpString);
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
                
                NSDictionary *defaultsDict = [NSDictionary dictionaryWithObjectsAndKeys:
                                              [NSNumber numberWithInt:50], @"Brightness-1", [NSNumber numberWithInt:50], @"Contrast-1",
                                              [NSNumber numberWithInt:50], @"Brightness-2", [NSNumber numberWithInt:50], @"Contrast-2",
                                              [NSNumber numberWithInt:50], @"Brightness-3", [NSNumber numberWithInt:50], @"Contrast-3",
                                              [NSNumber numberWithInt:0],  @"MinValue",     [NSNumber numberWithInt:100], @"MaxValue",
                                              [NSArray arrayWithObjects: @"DELL U2515H", @"My second Monitor", nil], @"Blacklist", nil];
                defaults = [NSUserDefaults standardUserDefaults];
                [defaults registerDefaults:defaultsDict];
                
                blacklistedDeviceWithNumber = 0;
                
                if ([useDefaults isEqualToString:@"n"]) {
                    MyLog(@"D: blacklist is disabled");
                }
                else if ([useDefaults isEqualToString:@"y"]) {
                    blacklistedDeviceWithNumber = displayId;
                    MyLog(@"I: using user-defaults to store current value");
                }
                else if ([useDefaults isEqualToString:@"c"]) {
                    blacklistedDeviceWithNumber = displayId;
                    MyLog(@"I: creating blacklist with %@", screenName);
                    MyLog(@"I: using user-defaults to store current value");
                    [defaults setObject:[NSArray arrayWithObjects:screenName, nil] forKey:@"Blacklist"];
                    [defaults synchronize];
                }
                else {
                    for (id object in (NSArray *)[defaults objectForKey:@"Blacklist"])
                    {
                        if ([(NSString *)object isEqualToString:screenName]) {
                            blacklistedDeviceWithNumber = displayId;
                            MyLog(@"I: found edid.name in blacklist");
                            MyLog(@"I: using user-defaults to store current value");
                            break;
                        }
                    }
                }

                if (dump_values) {
                    for (uint i=0x00; i<=255; i++)
                        getControl(cdisplay, i);
                    //MyLog(@"I: Dumped %x = %d\n", i, getControl(cdisplay, i));
                }
                
                
                [actions enumerateKeysAndObjectsUsingBlock:^(id argname, NSArray* valueArray, BOOL *stop) {
                    NSInteger control_id = [valueArray[0] intValue];
                    NSString *argval = valueArray[1];
                    MyLog(@"D: action: %@: %@", argname, argval);
                    
                    if (control_id > -1) {
                        // this is a valid monitor control
                        NSString *argval_num = [argval stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"-+"]]; // look for relative setting ops
                        if (argval != argval_num) {
                            // relative setting: read, calculate, then write
                            NSString *formula = [NSString stringWithFormat:@"%u %@ %@",
                                                 getControl(cdisplay, control_id),             // current
                                                 [argval substringFromIndex:argval.length - 1], // OP
                                                 argval_num                                     // new
                                                 ];
                            NSExpression *exp = [NSExpression expressionWithFormat:formula];
                            NSNumber *set_value = [exp expressionValueWithObject:nil context:nil];
                            
                            if (set_value.intValue >= [defaults integerForKey:@"MinValue"] && set_value.intValue <= [defaults integerForKey:@"MaxValue"]) {
                                MyLog(@"D: relative setting: %@ = %d", formula, set_value.intValue);
                                usleep(command_interval); // allow read to finish
                                setControl(cdisplay, control_id, set_value.unsignedIntValue);
                            } else {
                                MyLog(@"D: relative setting: %@ = %d is out of range!", formula, set_value.intValue);
                            }
                            
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
