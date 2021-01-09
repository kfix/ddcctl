#!/bin/bash
#tweak OSX display monitors' brightness to a given scheme, increment, or based on the current local time

hp="ddcctl -d 1"
len="ddcctl -d 2"

dim() {
	$hp -b 42 -c 26
	$len -b 4 -c 9
}

bright() {
	$hp -b 100 -c 75
	$len -b 85 -c 80
}

up() {
	$hp -b 20+ -c 12+
	$len -b 15+ -c 12+
}

down() {
	$hp -b 20- -c 12-
	$len -b 15- -c 12-
}

case "$1" in
	dim|bright|up|down) $1;;
	*)	#no scheme given, match local Hour of Day
		HoD=$(date +%k) #hour of day
		let "night = (( $HoD < 7 || $HoD > 18 ))" #daytime is 7a-7p
		(($night)) && dim || bright
		;;
esac
