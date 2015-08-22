ddcctl: DDC monitor controls for the OSX command line
----
Adjust your external monitors' built-in controls from the OSX shell:  
* brightness  
* contrast  

And *possibly* (if your monitor firmware is well implemented):  
* input source  
* built-in speaker volume  
* on/off/standby  

Code adapted from [DDC Panel](http://www.tonymacx86.com/graphics/90077-controlling-your-monitor-osx-ddc-panel.html#post554171) and [DDC-CI-Tools-for-OS-X](http://github.com/jontaylor/DDC-CI-Tools-for-OS-X).  
Also see [BrightnessMenulet](https://github.com/superduper/BrightnessMenulet), a nice StatusBar slider.  

For more info on the DDC protocol, read [HDMI – Hacking Displays Made Interesting](http://media.blackhat.com/bh-eu-12/Davis/bh-eu-12-Davis-HDMI-WP.pdf)


Install
----
```bash
make install
```

Usage
----
Run `ddcctl -h` for some options.  
[ddcctl.sh](/ddcctl.sh) is a script I use to control two PC monitors plugged into my Mac Mini.  
You can point Alfred, ControlPlane, or Karabiner at it to quickly switch presets.  

Caveats
----
`ddcctl` makes blocking I2C ioctl's to the OSX kernel.  
__YOUR MAC MIGHT CRASH__ when `ddcctl` changes monitor settings.  
* Don't file an issue if does, I can't debug OSX kernels and display drivers.  
* And don't test this out with a bunch of unsaved work open.  

__Your monitor itself might crash__ when making settings, especially the non-brightness/contrast ones.   
* Again, don't file an issue. Power cycle the monitor.  
* You just have to trial-and-error what works for your hardware.  

VGA cables seem to wreak havoc with DDC comms.  
Use DVI/DisplayPort/Thunderbolt if you can.  
 
