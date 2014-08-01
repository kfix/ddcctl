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

.PHONY: all clean install
