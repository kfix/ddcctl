#!/bin/make -f

CCFLAGS ?= -Wno-unused-variable

## Reply Transaction Type
## uncomment one only one
## comment both to use automatic detection
#CCFLAGS += -DTT_DDC
#CCFLAGS += -DTT_SIMPLE

## Uncomment to use an external app 'OSDisplay' to have a BezelUI-like OSD
##  provided by https://github.com/zulu-entertainment/OSDisplay
#CCFLAGS += -DOSD

INSTALL_DIR = /usr/local/bin
SOURCE_DIR = ./src

ifneq "$(strip $(filter debug, $(MAKECMDGOALS)))" ""
	CCFLAGS += -DDEBUG
	BUILD_DIR = ./build/debug
	PRODUCT_DIR = ./bin/debug
else
	CCFLAGS += -O3
	BUILD_DIR = ./build/release
	PRODUCT_DIR = ./bin/release
endif

all: clean $(PRODUCT_DIR)/ddcctl

intel nvidia: CCFLAGS += -DkDDCMinReplyDelay=1
intel nvidia: all

amd: CCFLAGS += -DkDDCMinReplyDelay=30000000
amd: all

debug: clean

$(BUILD_DIR)/%.o: $(SOURCE_DIR)/%.c
	@mkdir -p $(@D)
	$(CC) -Wall $(CCFLAGS) -c -o $@ $<

$(PRODUCT_DIR)/ddcctl: $(BUILD_DIR)/DDC.o
	@mkdir -p $(@D)
	$(CC) -Wall $(CCFLAGS) -o $@ -lobjc -framework IOKit -framework AppKit -framework Foundation $< $(SOURCE_DIR)/$(@F).m

install: $(PRODUCT_DIR)/ddcctl
	install $(PRODUCT_DIR)/ddcctl $(INSTALL_DIR)

clean:
	$(RM) $(BUILD_DIR)/*.o $(PRODUCT_DIR)/ddcctl

framebuffers:
	ioreg -c IOFramebuffer -k IOFBI2CInterfaceIDs -b -f -l -r -d 1

displaylist:
	ioreg -c IODisplayConnect -b -f -r -l -i -d 2

.PHONY: all debug clean install displaylist amd intel nvidia

