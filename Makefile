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
APR_CFG  := #$(shell apr-1-config --cflags --cppflags --includes --link-ld)
CCFLAGS   = -pipe -Wall -O3 -fomit-frame-pointer -fopenmp -pthread -march=$(ARCH) $(INCLUDES) $(APR_CFG) $(LINKER)
CXXFLAGS  = -std=c++17 $(CCFLAGS)

# Rust specific
RCFLAGS      = -C opt-level=3 -C codegen-units=1 # TODO -C lto

# Targets
RS_FILES := $(wildcard benchmarks/*/*.rs)
FILES    := $(wildcard benchmarks/*/*.c) $(wildcard benchmarks/*/*.cpp) $(RS_FILES)
ifdef SIMD
	FILES := $(FILES) $(addsuffix .simd, $(FILES))
endif
BINARIES := $(addsuffix .run, $(FILES))
BENCHES  := $(addsuffix .bm, $(FILES))

# Directory to mount tmpfs
TMP_DIR := tmp/

# Benchmark settings
FANNKUCH    := 12
FASTA       := 25000000
KNUCLEOTIDE := 25000000
MANDELBROT  := 16000
NBODY       := 50000000
PI          := 10000
REGEX       := 5000000
REVCOMP     := 25000000
SPECTRAL    := 5500
TREES       := 21
BM_OUT = $@

# Set a timeout of 5 min
TIMEOUT := -t 300

.PHONY: default cross bench-prep bench bench-test clean clean-benches clean-all

default: $(BINARIES)
cross: riscv64.run.tar.gz armv7l.run.tar.gz
bench: $(BENCHES)

# Reduced settings for testing
bench-test: FANNKUCH    := 7
bench-test: FASTA       := 1000
bench-test: KNUCLEOTIDE := 1000
bench-test: MANDELBROT  := 200
bench-test: NBODY       := 1000
bench-test: PI          := 30
bench-test: REGEX       := 1000
bench-test: REVCOMP     := 1000
bench-test: SPECTRAL    := 100
bench-test: TREES       := 10

bench-test: BM_OUT := -
bench-test: TIMEOUT := -t 5
bench-test: bench

# Pack bechmark results
pack: compiler_info.txt
	tar -czvf $(NODE)_$(shell date -I).tar.gz */*.bm compiler_info.txt

# Clean up
clean:
	@-rm -rf output
	@-rm -f benchmarks/*/*.run
	@-rm -f benchmarks/*/*.log
	@-rm -rf cargo/target
	@-rm -f riscv64.run.tar.gz armv7l.run.tar.gz
clean-benches:
	@-rm -f benchmarks/*/*.bm
clean-all: clean clean-benches

# Create tmpfs and set cpu frequencies
bench-prep:
	mkdir -p $(TMP_DIR)
	sudo mount -t tmpfs tmpfs $(TMP_DIR)
	sudo ./script/adjust-cpu-freq.sh $(FREQ)

# Special rule for benchmarking utility
output/bencher.run: bencher/bencher.c bencher/cpufreq.h bencher/fileutils.h
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
output/fannkuch-%.txt: benchmarks/fannkuch/1.c.run
	@mkdir -p output
	./$< $* > $@
output/fasta-%.txt: benchmarks/fasta/1.c.run
	@mkdir -p output
	./$< $* > $@
output/knucleotide-%.txt: benchmarks/knucleotide/1.cpp.run output/fasta-%.txt
	@mkdir -p output
	cat output/fasta-$*.txt | ./$< 0 > $@
output/mandelbrot-%.pbm: benchmarks/mandelbrot/2.c.run
	@mkdir -p output
	./$< $* > $@
output/nbody-%.txt: benchmarks/nbody/1.c.run
	@mkdir -p output
	./$< $* > $@
output/pi-%.txt: benchmarks/pi/1.c.run
	@mkdir -p output
	./$< $* > $@
output/regex-%.txt: benchmarks/regex/2.c.run output/fasta-%.txt
	@mkdir -p output
	cat output/fasta-$*.txt | ./$< 0 > $@
output/revcomp-%.txt: benchmarks/revcomp/2.c.run output/fasta-%.txt
	@mkdir -p output
	cat output/fasta-$*.txt | ./$< 0 > $@
output/spectral-%.txt: benchmarks/spectral/1.c.run
	@mkdir -p output
	./$< $* > $@
output/trees-%.txt: benchmarks/trees/1.c.run
	@mkdir -p output
	./$< $* > $@

# Collect compiler versions
compiler_info.txt: .FORCE
	@$(CC) --version | head -n 1 > $@
	@$(CXX) --version | head -n 1 >> $@

# fannkuch
.SECONDARY: output/fannkuch-$(FANNKUCH).txt
benchmarks/fannkuch/%: DEPENDS = output/fannkuch-$(FANNKUCH).txt
benchmarks/fannkuch/%: BENCH = ./output/bencher.run -diff output/fannkuch-$(FANNKUCH).txt $(TIMEOUT) $(BM_OUT) $< $(FANNKUCH)

# fasta
.SECONDARY: output/fasta-$(FASTA).txt
benchmarks/fasta/%: DEPENDS = output/fasta-$(FASTA).txt
benchmarks/fasta/%: BENCH = ./output/bencher.run -diff output/fasta-$(FASTA).txt $(TIMEOUT) $(BM_OUT) $< $(FASTA)

# knucleotide
.SECONDARY: output/fasta-$(KNUCLEOTIDE).txt output/knucleotide-$(KNUCLEOTIDE).txt
benchmarks/knucleotide/%: DEPENDS = output/fasta-$(KNUCLEOTIDE).txt output/knucleotide-$(KNUCLEOTIDE).txt
benchmarks/knucleotide/%: BENCH = ./output/bencher.run -i output/fasta-$(KNUCLEOTIDE).txt -diff output/knucleotide-$(KNUCLEOTIDE).txt $(TIMEOUT) $(BM_OUT) $< 0

# mandelbrot
.SECONDARY: output/mandelbrot-$(MANDELBROT).pbm
benchmarks/mandelbrot/%: DEPENDS = output/mandelbrot-$(MANDELBROT).pbm
benchmarks/mandelbrot/%: BENCH = ./output/bencher.run -diff output/mandelbrot-$(MANDELBROT).pbm $(TIMEOUT) $(BM_OUT) $< $(MANDELBROT)

# nbody
.SECONDARY: output/nbody-$(NBODY).txt
benchmarks/nbody/%: DEPENDS = output/nbody-$(NBODY).txt
benchmarks/nbody/%: BENCH = ./output/bencher.run -diff output/nbody-$(NBODY).txt -abserr 1.0e-8 $(TIMEOUT) $(BM_OUT) $< $(NBODY)

# pi
.SECONDARY: output/pi-$(PI).txt
benchmarks/pi/%: DEPENDS = output/pi-$(PI).txt
benchmarks/pi/%: BENCH = ./output/bencher.run -diff output/pi-$(PI).txt $(TIMEOUT) $(BM_OUT) $< $(PI)

# revcomp
.SECONDARY: output/fasta-$(REGEX).txt output/regex-$(REGEX).txt
benchmarks/regex/%: DEPENDS = output/fasta-$(REGEX).txt output/regex-$(REGEX).txt
benchmarks/regex/%: BENCH = ./output/bencher.run -i output/fasta-$(REGEX).txt -diff output/regex-$(REGEX).txt $(TIMEOUT) $(BM_OUT) $< 0

# revcomp
.SECONDARY: output/fasta-$(REVCOMP).txt output/revcomp-$(REVCOMP).txt
benchmarks/revcomp/%: DEPENDS = output/fasta-$(REVCOMP).txt output/revcomp-$(REVCOMP).txt
benchmarks/revcomp/%: BENCH = ./output/bencher.run -i output/fasta-$(REVCOMP).txt -diff output/revcomp-$(REVCOMP).txt $(TIMEOUT) $(BM_OUT) $< 0

# spectral
.SECONDARY: output/spectral-$(SPECTRAL).txt
benchmarks/spectral/%: DEPENDS = output/spectral-$(SPECTRAL).txt
benchmarks/spectral/%: BENCH = ./output/bencher.run -diff output/spectral-$(SPECTRAL).txt $(TIMEOUT) $(BM_OUT) $< $(SPECTRAL)

# trees
.SECONDARY: output/trees-$(TREES).txt
benchmarks/trees/%: DEPENDS = output/trees-$(TREES).txt
benchmarks/trees/%: BENCH = ./output/bencher.run -diff output/trees-$(TREES).txt $(TIMEOUT) $(BM_OUT) $< $(TREES)

# Always run benchmarks
.FORCE:

# Run benchmarks
.SECONDEXPANSION: # Adapt diff filenames
%.bm: COMMAND = $(BENCH)
%.simd.bm: COMMAND = if ! diff $*.run $*.simd.run >/dev/null; then $(BENCH); fi

%.simd.bm: %.simd.run $$(DEPENDS) output/bencher.run .FORCE
	-$(COMMAND)
%.bm: %.run $$(DEPENDS) output/bencher.run bench-prep .FORCE
	-$(COMMAND)

# Packed cross compiled binaries
CROSS_FILES = $(addsuffix .$(*F).run, $(RS_FILES))
.SECONDARY: $$(CROSS_FILES)
%.run.tar.gz: $$(CROSS_FILES)
	tar -czvf $@ $(CROSS_FILES)
