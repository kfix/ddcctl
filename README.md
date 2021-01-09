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

# Install #
## Download Binaries ##
Head to [Releases](https://github.com/kfix/ddcctl/releases) and from the
[latest release](https://github.com/kfix/ddcctl/releases/latest) download
[`ddcctl_binaries.zip`](https://github.com/kfix/ddcctl/releases/latest/download/ddcctl_binaries.zip)
archive that holds `ddcctl-intel`, `ddcctl-amd` and `ddcctl-nvidia` binaries
respectively for Intel, AMD and Nvidia GPUs.

## Build from Source ##
* install Xcode
* figure out if your Mac is using an Intel, Nvidia or AMD GPU
* run `make intel` or make `make nvidia` or `make amd`

# Usage #
Run `ddcctl -h` for some options.  
[ddcctl.sh](/scripts/ddcctl.sh) is a script I use to control two PC monitors plugged into my Mac Mini.
You can point Alfred, ControlPlane, or Karabiner at it to quickly switch presets.

# Input Sources #
When setting input source, refer to the table below to determine which value to
use. For example, to set your first display to HDMI: `ddcctl -d 1 -i 17`.

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
`ddcctl.m` sprang from a
[forum thread](https://www.tonymacx86.com/threads/controlling-your-monitor-with-osx-ddc-panel.90077/page-6#post-795208) on the TonyMac-x86 boards.

`DDC.c` originated from [jontaylor/DDC-CI-Tools-for-OS-X](https://github.com/jontaylor/DDC-CI-Tools-for-OS-X), but was reworked by others on the forums.  

A few forks have also backported patches, which is *nice* :ok_hand:.
