# PicoTerm build. Needs sjasmplus (1.20 or later) and Python 3.

SJASMPLUS ?= sjasmplus
PYTHON    ?= $(if $(wildcard .venv/bin/python),.venv/bin/python,python3)

# Above STKEND + 1B00h, which CHNG_VID needs free (src/hw/scld.asm).
ORG   := 0x8800
BUILD := build
SRC   := $(shell find src -name '*.asm' -o -name '*.inc')

.PHONY: all clean test venv

# sjasmplus writes its output even when assembly fails: don't keep it.
.DELETE_ON_ERROR:

all: $(BUILD)/picoterm.tap

$(BUILD):
	mkdir -p $@

$(BUILD)/picoterm.bin: $(SRC) | $(BUILD)
	$(SJASMPLUS) --nologo --msg=war -DORG_ADDR=$(ORG) --inc=src \
		--raw=$@ --sym=$(BUILD)/picoterm.sym --lst=$(BUILD)/picoterm.lst \
		src/main.asm

$(BUILD)/picoterm.tap: $(BUILD)/picoterm.bin tools/mktap.py
	$(PYTHON) tools/mktap.py --org $(ORG) --name PicoTerm $< $@

test: $(BUILD)/picoterm.tap
	$(PYTHON) -m unittest discover -s tests -v

# The host tests need the z80 package; without it they're skipped.
venv:
	python3 -m venv .venv
	.venv/bin/pip install -r tests/requirements.txt

clean:
	rm -rf $(BUILD)
