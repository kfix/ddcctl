#!/bin/make -f

CCFLAGS =

## Reply Transaction Type
## uncomment one only one
## comment both to use automatic detection
#CCFLAGS += -DTT_DDC
#CCFLAGS += -DTT_SIMPLE

## Uncomment to use Blacklist (read/write values to/from user-defaults)
#CCFLAGS += -DBLACKLIST

## Uncomment to use an external app 'OSDisplay' to have a BezelUI like OSD
#CCFLAGS += -DOSD

all: clean ddcctl

debug: CCFLAGS += -DDEBUG
debug: clean ddcctl

%.o: %.c
	gcc $(CCFLAGS) -Wall -c -o $@ $<
	
ddcctl: DDC.o
	gcc $(CCFLAGS) -Wall -o $@ -lobjc -framework IOKit -framework AppKit -framework Foundation $< $@.m

install: ddcctl
	install ddcctl /usr/local/bin

clean:
	-rm *.o ddcctl

.PHONY: all clean install
