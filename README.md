ddcctl: DDC monitor controls for the OSX command line
----
Adjust your external monitors' built-in controls from the OSX shell:  
* brightness  
* contrast  

And *possibly* (if your monitor firmware is well implemented):  
* input source  
* built-in speaker volume  
* on/off/standby 
* rgb colors
* color presets
* reset 

Install
----
```bash
make install
```

For an On-Screen Display using [OSDisplay.app](https://github.com/zulu-entertainment/OSDisplay):  
`make CCFLAGS=-DOSD clean ddcctl`

Usage
----
Run `ddcctl -h` for some options.  
[ddcctl.sh](/ddcctl.sh) is a script I use to control two PC monitors plugged into my Mac Mini.  
You can point Alfred, ControlPlane, or Karabiner at it to quickly switch presets.  

Known Bugs / Caveats
----
`ddcctl` gets a lot of bug reports for stuff that can't be remotely debugged or fixed.  
Please include pertinent information on your monitors, Macintosh, and macOS.
Be warned, here are the four main issues I will close out-of-hand:  

__MY HACKINTOSH <whatever>__:  
You're on your own with Hackintoshes.  

__YOUR PC MONITOR MAY SUCK AT DDC__  
The DDC standard is very loosely implemented by monitor manufacturers beyond sleeping the display.  
* This is because Windows doesn't use brightness sensors to dim screens like OSX does —via USB, not DDC!
* Adjusting brightness, contrast, and super-awesome-multimedia-frobber-mode may not be possible.   

__YOUR MONITOR MIGHT FREEZE__ when making settings, especially the non-brightness/contrast ones.   
* Power cycle the monitor.  
* You just have to trial-and-error what works for your hardware.  

VGA cables seem to wreak havoc with DDC comms.  
Use DVI/DisplayPort/Thunderbolt if you can.  
 
