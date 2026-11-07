#!/bin/sh
# Build the vip_core testbench (run in WSL).
cd "$(dirname "$0")"
verilator --cc --exe --build -O2 -Wno-fatal -Wno-WIDTHEXPAND --public-flat-rw \
	--top-module vip_core -Mdir obj_dir \
	../rtl/cdp1802.sv ../rtl/cdp1861.sv ../rtl/vip_core.sv tb.cpp -o tb
