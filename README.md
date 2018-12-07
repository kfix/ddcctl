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

Input Sources
----
When setting input source, refer to the table below to determine which value to use. For example, to set your first display to HDMI: `ddcctl -d 1 -i 17`

| Input Source | Value        |
| ------------- |-------------|
| VGA-1 | 1 |
| VGA-2 | 2 |
| DVI-1 | 3 |
| DVI-2 | 4 |
| Composite video 1 | 5 |
| Composite video 2 | 6 |
| S-Video-1 | 7 |
| S-Video-2 | 8 |
| Tuner-1 | 9 |
| Tuner-2 | 10 |
| Tuner-3 | 11 |
| Component video (YPrPb/YCrCb) 1 | 12 |
| Component video (YPrPb/YCrCb) 2 | 13 |
| Component video (YPrPb/YCrCb) 3 | 14 |
| DisplayPort-1 | 15 |
| DisplayPort-2 | 16 |
| HDMI-1 | 17 |
| HDMI-2 | 18 |
