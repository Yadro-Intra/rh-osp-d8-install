# Makefile #

CFLAGS=-Wall
CC=gcc
RM=rm -f
SUDO=sudo
ENV=env

.PHONY: all clean test

all:		recvRawEth

clean:
	$(RM)	recvRawEth

test:		recvRawEth
	@set -e; \
	$(SUDO) -E ./recvRawEth -a -c5 \
		-I`ip -o link | grep -vm1 LOOPBACK | cut -d: -f2 | tr -d '[ \t]'`

recvRawEth:	recvRawEth.c

# EOF #
