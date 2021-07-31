# ddcctl: DDC monitor controls for the OSX command line #
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

# Project Status #
This is a GPLv3 open source repo and you may use it in the ways that license allows.  

It is not a Community "Free Software" Project - its decidedly my personal utility and its in the (dreaded/loved) _"maintenance mode"_.

I don't have the time currently to accept new Issues and do triaging of all the non-bugs being reported.  

If you have issues with your OS and hardware, its up to you to debug them and (optionally) PR your fixes (see bottom section) if you'd like to share them.  

# Installation #

## Option 1: Install via Homebrew ##
Open a terminal window and run `$ brew install ddcctl`.

## Option 2: Download Binaries ##
Head to [Releases](https://github.com/kfix/ddcctl/releases) and from the
[latest release](https://github.com/kfix/ddcctl/releases/latest) download
[`ddcctl_binaries.zip`](https://github.com/kfix/ddcctl/releases/latest/download/ddcctl_binaries.zip)
archive

## Option 3: Build from Source ##
* install Xcode
* run `make`

# Usage #
Run `ddcctl -h` for some options.  
[ddcctl.sh](/scripts/ddcctl.sh) is a script I use to control two PC monitors plugged into my Mac Mini.  
You can point Alfred, ControlPlane, or Karabiner at it to quickly switch presets.

# Input Sources #
When setting input source, refer to the table below to determine which value to use.  
For example, to set your first display to HDMI: `ddcctl -d 1 -i 17`.

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
| USB-C | 27 |

# Credits #
`ddcctl.m` sprang from a [forum thread](https://www.tonymacx86.com/threads/controlling-your-monitor-with-osx-ddc-panel.90077/page-6#post-795208) on the TonyMac-x86 boards.

`DDC.c` originated from [jontaylor/DDC-CI-Tools-for-OS-X](https://github.com/jontaylor/DDC-CI-Tools-for-OS-X), but was reworked by others on the forums.  

A few forks have also backported patches, which is *nice* :ok_hand:.

# Contributing PRs #

bug-fix & non-bug-fix/feature PRs have the same broad guidelines:
* well described as to the universal utility of the change for the (presumed) majority of users / developers
  * or a positive proof that the change doesn't detract from the usability for the majority of users
* easy to test
  * provide _your_ test procedure, if you have one!
  * keep in mind my verification is always manual - I don't have a CI system wired up to a bank of real Macs & monitors

As to additional criteria for new-features, please understand that `ddcctl` currently does what _I need it to do_ on my own all-Apple fleet.

There is a [backlog](https://github.com/kfix/ddcctl/projects/1) of some (broadly desirable) features that came from reported issues. PRs are encouraged to address these!  

I'm not really interested in adding any features that I have no ability or desire to support on my own hardware.  

Unfortunately, I cannot make a time-to-review estimation - but the simpler/cleaner a PR is, the the faster its likely to get reviewed & merged.
