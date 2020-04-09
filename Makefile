# Use -march=native by default
ARCH := native
# TODO investiage why simd difference is almost non-existent
# SIMD := true

# Change flags based on node/machine
NODE := $(shell uname -n)
MACHINE := $(shell uname -m)
ifeq "$(NODE)" "freedom-u540"
	undefine SIMD
	ARCH := rv64gc
	FREQ := 999999
else ifeq "$(NODE)" "raspberrypi"
	FREQ := 1
endif

# Compilers and flags
CC  := gcc
CXX := g++
RC  := rustc
# Indirect assignment to allow changing $(ARCH)
INCLUDES := -I/usr/include/re2 -I/usr/include/klib
LINKER   := -lm -lgmp -lpcre #-lpcre2-8 -lboost_regex -lboost_thread -lre2
APR_CFG  := $(shell apr-1-config --cflags --cppflags --includes --link-ld)
CCFLAGS   = -pipe -Wall -O3 -fomit-frame-pointer -fopenmp -pthread -march=$(ARCH) $(INCLUDES) $(APR_CFG) $(LINKER)
CXXFLAGS  = -std=c++17 $(CCFLAGS)

# Rust specific
RCFLAGS      = -C opt-level=3 -C codegen-units=1 # TODO -C lto

# Targets
RS_FILES := $(wildcard */*.rs)
FILES    := $(wildcard */*.c) $(wildcard */*.cpp) $(RS_FILES)
ifdef SIMD
	FILES := $(FILES) $(addsuffix .simd, $(FILES))
endif
BINARIES := $(addsuffix .run, $(FILES))
BENCHES  := $(addsuffix .bm, $(FILES))

# Directory to mount tmpfs
TMP_DIR := tmp/

# Benchmark settings
FASTA    := 25000000
NBODY    := 50000000
REVCOMP  := 25000000
SPECTRAL := 5500
TREES    := 21
BM_OUT = $@

# Set a timeout of 5 min
TIMEOUT := -t 300

.PHONY: default cross bench-prep bench bench-test clean clean-benches clean-all

default: $(BINARIES)
cross: riscv64.run.tar.gz armv7l.run.tar.gz
bench: $(BENCHES)

# Reduced settings for testing
bench-test: FASTA    := 1000
bench-test: NBODY    := 1000
bench-test: REVCOMP  := 1000
bench-test: SPECTRAL := 100
bench-test: TREES    := 10

bench-test: BM_OUT := -
bench-test: TIMEOUT := -t 5
bench-test: bench

# Pack bechmark results
pack: compiler_info.txt
	tar -czvf $(NODE)_$(shell date -I).tar.gz */*.bm compiler_info.txt

# Clean up
clean:
	@-rm -f bencher
	@-rm -f */*.run
clean-benches:
	@-rm -f */*.bm
clean-all: clean clean-benches
	@-rm -rf output

# Create tmpfs and set cpu frequencies
bench-prep:
	mkdir -p $(TMP_DIR)
	sudo mount -t tmpfs tmpfs $(TMP_DIR)
	sudo ./adjust-cpu-freq.sh $(FREQ)

# Special rule for benchmarking utility
bencher: bencher.c cpufreq.h fileutils.h
	$(CC) $(CCFLAGS) -DISA_NAME='"$(MACHINE)"' $< -o $@

# Compile benchmark binaries
%.c.run: %.c
	$(CC) $< -o $@ $(CCFLAGS) -fno-tree-vectorize
%.cpp.run: %.cpp
	$(CXX) $< -o $@ $(CXXFLAGS) -fno-tree-vectorize

%.c.simd.run: %.c
	$(CC) $(CCFLAGS) $< -o $@
%.cpp.simd.run: %.cpp
	$(CXX) $(CXXFLAGS) $< -o $@

# Cross compilation rules
ifeq "$(MACHINE)" "x86_64"
RUST_TARGET :=
RUST_DEPS   := cargo/target/deps
CARGO_FLAGS := --release
RUST_CRATES  = $(shell cat $(RUST_DEPS))

%.rs.riscv64.run: RUST_TARGET := -C linker=riscv64-linux-gnu-gcc --target=riscv64gc-unknown-linux-gnu
%.rs.riscv64.run: RUST_DEPS = cargo/target/deps-riscv64

%.rs.armv7l.run: RUST_TARGET := -C linker=arm-linux-gnueabihf-gcc --target=armv7-unknown-linux-gnueabihf
%.rs.armv7l.run: RUST_DEPS = cargo/target/deps-armv7l

# Needs to be one target to prevent concurrent cargo runs
cargo/target/deps_marker: cargo/Cargo.toml cargo/Cargo.lock
	$(MAKE) -C cargo target/deps RCFLAGS="$(RCFLAGS)" CARGO_FLAGS="$(CARGO_FLAGS)"
	$(MAKE) -C cargo target/deps-riscv64 RCFLAGS="$(RCFLAGS) -C linker=riscv64-linux-gnu-gcc" CARGO_FLAGS="$(CARGO_FLAGS) --target=riscv64gc-unknown-linux-gnu --target-dir=target/riscv64"
	$(MAKE) -C cargo target/deps-armv7l RCFLAGS="$(RCFLAGS) -C linker=arm-linux-gnueabihf-gcc" CARGO_FLAGS="$(CARGO_FLAGS) --target=armv7-unknown-linux-gnueabihf --target-dir=target/armv7l"
	@touch $@

%.rs.riscv64.run %.rs.armv7l.run %.rs.run: %.rs cargo/target/deps_marker
	$(RC) $(RUST_TARGET) $(RCFLAGS) $(RUST_CRATES) $< -o $@
else
%.rs.run: $(MACHINE).run.tar.gz
	tar -xzvf $^ $*.rs.$(MACHINE).run
	mv $*.rs.$(MACHINE).run $@
endif

# Diff files
output/fasta-%.txt: fasta/1.c.run
	@mkdir -p output
	./$< $* > $@
output/nbody-%.txt: nbody/1.c.run
	@mkdir -p output
	./$< $* > $@
output/revcomp-%.txt: revcomp/4.c.run output/fasta-%.txt
	@mkdir -p output
	cat output/fasta-$*.txt | ./$< 0 > $@
output/spectral-%.txt: spectral/1.c.run
	@mkdir -p output
	./$< $* > $@
output/trees-%.txt: trees/1.c.run
	@mkdir -p output
	./$< $* > $@

# Collect compiler versions
compiler_info.txt: .FORCE
	@$(CC) --version | head -n 1 > $@
	@$(CXX) --version | head -n 1 >> $@

# fasta
.SECONDARY: output/fasta-$(FASTA).txt
fasta/%: DEPENDS = output/fasta-$(FASTA).txt
fasta/%: BENCH = ./bencher -diff output/fasta-$(FASTA).txt $(TIMEOUT) $(BM_OUT) $< $(FASTA)

# nbody
.SECONDARY: output/nbody-$(NBODY).txt
nbody/%: DEPENDS = output/nbody-$(NBODY).txt
nbody/%: BENCH = ./bencher -diff output/nbody-$(NBODY).txt -abserr 1.0e-8 $(TIMEOUT) $(BM_OUT) $< $(NBODY)

# revcomp
.SECONDARY: output/fasta-$(REVCOMP).txt output/revcomp-$(REVCOMP).txt
revcomp/%: DEPENDS = output/fasta-$(REVCOMP).txt output/revcomp-$(REVCOMP).txt
revcomp/%: BENCH = ./bencher -i output/fasta-$(REVCOMP).txt -diff output/revcomp-$(REVCOMP).txt $(TIMEOUT) $(BM_OUT) $< 0

# spectral
.SECONDARY: output/spectral-$(SPECTRAL).txt
spectral/%: DEPENDS = output/spectral-$(SPECTRAL).txt
spectral/%: BENCH = ./bencher -diff output/spectral-$(SPECTRAL).txt $(TIMEOUT) $(BM_OUT) $< $(SPECTRAL)

# trees
.SECONDARY: output/trees-$(TREES).txt
trees/%: DEPENDS = output/trees-$(TREES).txt
trees/%: BENCH = ./bencher -diff output/trees-$(TREES).txt $(TIMEOUT) $(BM_OUT) $< $(TREES)

# Always run benchmarks
.FORCE:

# Run benchmarks
.SECONDEXPANSION: # Adapt diff filenames
%.bm: COMMAND = $(BENCH)
%.simd.bm: COMMAND = if ! diff $*.run $*.simd.run >/dev/null; then $(BENCH); fi

%.simd.bm: %.simd.run $$(DEPENDS) bencher .FORCE
	-$(COMMAND)
%.bm: %.run $$(DEPENDS) bencher bench-prep .FORCE
	-$(COMMAND)

# Packed cross compiled binaries
CROSS_FILES = $(addsuffix .$(*F).run, $(RS_FILES))
.SECONDARY: $$(CROSS_FILES)
%.run.tar.gz: $$(CROSS_FILES)
	tar -czvf $@ $(CROSS_FILES)
