# Makefile #

CFLAGS=-Wall
CC=gcc
RM=rm -f
SUDO=sudo
ENV=env
INSTALL=install
BIN_DIR=$(HOME)/bin

.PHONY: all clean test install

all:		recvRawEth

clean:
	$(RM)	recvRawEth

test:		recvRawEth
	@set -e; \
	$(SUDO) -E ./recvRawEth -a -c5 \
		-I`ip -o link | grep -vm1 LOOPBACK | cut -d: -f2 | tr -d '[ \t]'`

install:	recvRawEth
	$(INSTALL) $< $(BIN_DIR)/

recvRawEth:	recvRawEth.c

# EOF #
