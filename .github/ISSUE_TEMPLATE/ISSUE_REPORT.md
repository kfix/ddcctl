---
name: General Issue
about: Guidelines for reporting issues with ddcctl
---

Sending just an error message is not enough!  
Requirements for submitters
--
Errors are a warning for you (the unknown monitor & Mac owner) and  
do not in-and-of-themselves mean there is a bug in `ddcctl`.

You must include pertinent information on your monitors, Macintosh, and macOS, or else  
your issue will get an `incomplete` tag.

Making & running a debug build (`make debug`) and reproducing your issue to provide  
detailed output for the report is highly encouraged!  

Known issues
--
I _will_ close reports about these issues out-of-hand:  

### __MY HACKINTOSH <whatever>__:  
You're on your own with Hackintoshes.  

### __YOUR MONITOR MAY NOT CORRECTLY SUPPORT MUCH OF DDC__  
The DDC standard is very loosely implemented by monitor manufacturers beyond sleeping the display.  
* This is because Windows doesn't use brightness sensors to dim screens like OSX does —via USB, not DDC!
* Adjusting brightness, contrast, and super-awesome-multimedia-frobber-mode may not be possible.  

### __YOUR MONITOR MIGHT FREEZE__ when making settings, especially the non-brightness/contrast ones.  
* Power cycle the monitor.  
* You just have to trial-and-error what works for your hardware.  

Practical advice
--
VGA cables seem to wreak havoc with DDC comms.  
Use DVI/DisplayPort/Thunderbolt if you can.

Please consider that there is no team working on `ddcctl`, it is a fun-time project  
that has long-since been considered "finished".  

Bad, incomplete, or *lazy* reports and non-bugs are not fun to work on  
so I *will* be cranky towards their reporters who didn't heed these instructions.  
