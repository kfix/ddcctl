#!/bin/bash
#tweak OSX display monitors' brightness to a given scheme, increment, or based on the current local time

hp="ddcctl -d 1"
#len="ddcctl -d 2"

poweroff() {
    # Power button will need pressing to power back on
    $hp -p 5
}

volmute() {
    # Set volume to 0 / mute
    newvol=0
    volume=$newvol
    $hp -v $newvol
}

voldown() {
    # Decrement the volume by one
    newvol=$((volume-1))
    # But dont be negative
    [[ $newvol -lt 0 ]] && newvol=0
    volume=$newvol
    $hp -v $newvol
}

volup() {
    # Increment the volume by one
    newvol=$((volume+1))
    # But cap at 30 so we dont damage anything
    [[ $newvol -gt 30 ]] && newvol=30
    volume=$newvol
    $hp -v $volume
}

dim() {
    $hp -b 42 -c 26
    #$len -b 4 -c 9
}

bright() {
    $hp -b 100 -c 75
    #$len -b 85 -c 80
}

up() {
    newb=$((brightness+10))
    [[ $newb -gt 100 ]] && newb=100
    brightness=$newb
    $hp -b $brightness -c 12+
    #$len -b $brightness -c 12+
}

down() {
    newb=$((brightness-10))
    [[ $newb -lt 0 ]] && newb=0
    brightness=$newb
    $hp -b $brightness -c 12-
    #$len -b 20- -c 12-
}

init() {
    state_file="$HOME/.ddc_control_state"
    if [[ ! -f $state_file ]]; then
        echo "Creating a new state file... ($state_file)"
        touch "$state_file" || exit 1
    else
        echo "Reading state file... ($state_file)"
        # shellcheck source=/dev/null
        source "$state_file"
    fi

    if [[ -z "$volume" ]]; then
        volume=5
        echo "No state [volume]     (setting to $volume)"
    elif [[ -z "$brightness" ]]; then
        brightness=42
        echo "No state [brightness] (setting to $brightness)"
    elif [[ -z "$contrast" ]]; then
        contrast=70
        echo "No state [contrast]   (setting to $contrast)"
    fi
}

savestate() {
    echo "Saving state to file..."
    cat <<EOF > "$state_file"
export volume=$volume
export brightness=$brightness
export contrast=$contrast
EOF
}

case "$1" in
    dim|bright|up|down) init; $1; savestate;;
    volmute) init; $1;;
    voldown|volup) init; $1; savestate;;
    poweroff) init; $1;;
    *)  #no scheme given, match local Hour of Day
        #HoD=$(date +%k) #hour of day
        #let "night = (( $HoD < 7 || $HoD > 18 ))" #daytime is 7a-7p
        #(($night)) && dim || bright
        ;;
esac
