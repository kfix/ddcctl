#!/usr/bin/env bash

function get_primary_brightness() {
  declare -A bparams
  brightness_string=$(ioreg -c AppleBacklightDisplay | grep -o '"brightness"=[^}]*}')

  # this should be something like `"brightness"={"min"=0,"max"=65535,"value"=4108}`, pull out the #'s
  # order doesn't matter
  while IFS='=' read -r -a array; do
    bparams[${array[0]}]=${array[1]}
  done <<< $(echo "$brightness_string" | egrep -o '"(min|max|value)"=[0-9]+' | sed 's,",,g')

  brightness=$(bc <<< "scale=2; 100 * (${bparams[value]} / ${bparams[max]})" | cut -d'.' -f1)
  echo $brightness
}

function set_external_brightness() {
  echo "Setting external brightness to: $1"

  for i in $(seq $(./ddcctl 2>&1 | grep 'found [0-9]' | grep -o '[0-9]')); do
    ./ddcctl -d $i -b $1 2>&1 > /dev/null
  done
}

last_brightness=-1
while true; do
  brightness=$(get_primary_brightness)
  if [ $last_brightness != $brightness ]; then
    last_brightness=$brightness
    echo "Updating brightness to $brightness"
    set_external_brightness $brightness
  fi
  sleep 0.1
done
