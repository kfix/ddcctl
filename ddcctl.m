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
//  In save-mode the app reads current value twice to be sure. Use '-s y' to activate.
//
//  Have fun!
//

#ifdef NDEBUG
#define MyLog(...) (void)printf("%s\n",[[NSString stringWithFormat:__VA_ARGS__] UTF8String])
#else
#define MyLog NSLog
#endif

#import <Foundation/Foundation.h>
#import <AppKit/NSScreen.h>
#import "DDC.h"

NSUserDefaults *defaults;
int blacklistedDeviceWithNumber;
bool save_mode;

NSString *EDIDString(char *string)
{
    NSString *temp = [[NSString alloc] initWithBytes:string length:13 encoding:NSASCIIStringEncoding];
    return ([temp rangeOfString:@"\n"].location != NSNotFound) ? [[temp componentsSeparatedByString:@"\n"] objectAtIndex:0] : temp;
}

uint get_control(CGDirectDisplayID cdisplay, uint control_id)
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
        
        if (save_mode) {
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

void set_control(CGDirectDisplayID cdisplay, uint control_id, uint new_value)
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
}

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
        MyLog(@"I: found %lu displays", [_displayIDs count]);
        
        NSDictionary *argpairs = [[NSUserDefaults standardUserDefaults] volatileDomainForName:NSArgumentDomain];
        NSDictionary *switches = @{ // @MCCS:VCP codes we support from http://wenku.baidu.com/view/9a94824c767f5acfa1c7cd80.html
                                   @"b": @BRIGHTNESS,
                                   @"c": @CONTRAST,
                                   @"d": @-1,                   // set_display consumed by app
                                   @"D": @-1,                   // dump_values consumed by app
                                   @"w": @100000,               // command_interval consumed by app
                                   @"p": @DPMS,                 //
                                   @"i": @INPUT_SOURCE,         // pg85
                                   @"m": @AUDIO_MUTE,
                                   @"v": @AUDIO_SPEAKER_VOLUME, // pg94
                                   @"o": @ORIENTATION,
                                   @"u": @-1,                   // use user-defaults to store current value
                                   @"s": @-1,                   // save-mode: read current value twice to be sure
                                   }; // should test against http://www.entechtaiwan.com/lib/softmccs.shtm
        
        NSString *screenName = @"";
        NSUInteger command_interval = [[NSUserDefaults standardUserDefaults] integerForKey:@"w"];
        NSUInteger set_display = [[NSUserDefaults standardUserDefaults] integerForKey:@"d"];
        NSString *useDefaults = [[NSUserDefaults standardUserDefaults] stringForKey:@"u"];
        save_mode = ([[[NSUserDefaults standardUserDefaults] stringForKey:@"s"] isEqualToString:@"y"]) ? true : false;
        
        if (0 < set_display && set_display <= [_displayIDs count]) {
            MyLog(@"I: polling display %lu's EDID", set_display);
            CGDirectDisplayID cdisplay = (CGDirectDisplayID)[_displayIDs pointerAtIndex:set_display - 1];
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
                    blacklistedDeviceWithNumber = set_display;
                    MyLog(@"I: using user-defaults to store current value");
                }
                else if ([useDefaults isEqualToString:@"c"]) {
                    blacklistedDeviceWithNumber = set_display;
                    MyLog(@"I: creating blacklist with %@", screenName);
                    MyLog(@"I: using user-defaults to store current value");
                    [defaults setObject:[NSArray arrayWithObjects:screenName, nil] forKey:@"Blacklist"];
                    [defaults synchronize];
                }
                else {
                    for (id object in (NSArray *)[defaults objectForKey:@"Blacklist"])
                    {
                        if ([(NSString *)object isEqualToString:screenName]) {
                            blacklistedDeviceWithNumber = set_display;
                            MyLog(@"I: found edid.name in blacklist");
                            MyLog(@"I: using user-defaults to store current value");
                            break;
                        }
                    }
                }

                NSUInteger dump_values = [[NSUserDefaults standardUserDefaults] integerForKey:@"D"];
                if (0 < dump_values) {
                    for(uint i=0x00; i<=255; i++)
                        get_control(cdisplay, i);
                    //MyLog(@"I: Dumped %x = %d\n", i, get_control(cdisplay, i));
                }
                
                [argpairs enumerateKeysAndObjectsUsingBlock:^(id argname, NSString* argval, BOOL *stop) {
                    MyLog(@"D: command arg-pair: %@: %@", argname, argval);
                    
                    NSInteger control_id = [[switches valueForKey:argname] intValue];
                    if (control_id > -1) {
                        // this is a valid monitor control from switches
                        NSString *argval_num = [argval stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"-+"]]; // look for relative setting ops
                        if (argval != argval_num) {
                            // relative setting: read, calculate, then write
                            NSString *formula = [NSString stringWithFormat:@"%u %@ %@",
                                                 get_control(cdisplay, control_id),             // current
                                                 [argval substringFromIndex:argval.length - 1], // OP
                                                 argval_num                                     // new
                                                 ];
                            NSExpression *exp = [NSExpression expressionWithFormat:formula];
                            NSNumber *set_value = [exp expressionValueWithObject:nil context:nil];
                            
                            if (set_value.intValue >= [defaults integerForKey:@"MinValue"] && set_value.intValue <= [defaults integerForKey:@"MaxValue"]) {
                                MyLog(@"D: relative setting: %@ = %d", formula, set_value.intValue);
                                usleep(command_interval); // allow read to finish
                                set_control(cdisplay, control_id, set_value.unsignedIntValue);
                            } else {
                                MyLog(@"D: relative setting: %@ = %d is out of range!", formula, set_value.intValue);
                            }
                            
                        } else if ([argval hasPrefix:@"?"]) {
                            // read current setting
                            get_control(cdisplay, control_id);
                        } else {
                            // write fixed setting
                            set_control(cdisplay, control_id, [argval intValue]);
                        }
                    }
                    usleep(command_interval); // stagger comms to these wimpy I2C mcu's
                }];
                
            } else {
                MyLog(@"E: Failed to poll display!");
                return -1;
            }
        } else { // no display id given
            MyLog(@"Usage:\n\
ddcctl -d <1-..>  [display#]\n\
       -w 100000  [delay usecs between settings]\n\
\
----- Basic settings -----\n\
       -b <1-..>  [brightness]\n\
       -c <1-..>  [contrast]\n\
       -u <y|n|c> [blacklist on|off|create]\n\
       -s <y|n>   [save-mode: read current value twice to be sure on|off]\n\
\
----- Settings that don\'t always work -----\n\
       -m <1|2>   [mute speaker OFF/ON]\n\
       -v <1-254> [speaker volume]\n\
       -i <1-12>  [select input source]\n\
       -p <1|2-5> [power on | standby/off]\n\
       -o         [read-only orientation]\n\
\
----- Setting grammar -----\n\
       -X ? (queries setting X)\n\
       -X NN (setting X to NN)\n\
       -X <NN>- (decreases setting X by NN)\n\
       -X <NN>+ (increases setting X by NN)");
        }
    }
    return 0;
}
