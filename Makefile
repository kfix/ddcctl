#!/bin/make -f

all: clean ddcctl

%.o: %.c
	gcc -Wall -c -o $@ $<
	
ddcctl: DDC.o
	gcc -Wall -o $@ -lobjc -framework IOKit -framework AppKit -framework Foundation $< $@.m

install: ddcctl
	install ddcctl /usr/local/bin

clean:
	-rm *.o ddcctl

framebuffers:
	ioreg -c IOFramebuffer -k IOFBI2CInterfaceIDs -b -f -l -r -d 1

displaylist:
	ioreg -c IODisplayConnect -b -f -r -l -i -d 2

.PHONY: all clean install displaylist
