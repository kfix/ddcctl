#!/bin/make -f

CCFLAGS ?=

## Reply Transaction Type
## uncomment one only one
## comment both to use automatic detection
#CCFLAGS += -DTT_DDC
#CCFLAGS += -DTT_SIMPLE

## Uncomment to use an external app 'OSDisplay' to have a BezelUI like OSD
#CCFLAGS += -DOSD

all: clean ddcctl

debug: CCFLAGS += -DDEBUG
debug: clean ddcctl

%.o: %.c
	$(CC) $(CCFLAGS) -Wall -c -o $@ $<

ddcctl: DDC.o
	$(CC) $(CCFLAGS) -Wall -o $@ -lobjc -framework IOKit -framework AppKit -framework Foundation $< $@.m

install: ddcctl
	install ddcctl /usr/local/bin

clean:
	$(RM) *.o ddcctl

framebuffers:
	ioreg -c IOFramebuffer -k IOFBI2CInterfaceIDs -b -f -l -r -d 1

displaylist:
	ioreg -c IODisplayConnect -b -f -r -l -i -d 2

.PHONY: all clean install displaylist
