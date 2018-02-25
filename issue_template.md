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

### __I HAVE TWO IDENTICAL MONITORS AND ONE DOESN'T WORK__:  
This is already known: #17  

No patch has been submitted to resolve this, but the essential facts have  
been gathered to work from.  

Any suggestion to revert the master branch to an obsolete version  
to work-around this will be rejected.  

Release and mantain your own fork if this bothers you.  
I do not work for you and will not be providing backports for your convienience.  

### __YOUR PC MONITOR MAY SUCK AT DDC__  
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
