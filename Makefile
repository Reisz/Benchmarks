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
# Indirect assignment to allow changing $(ARCH)
CCFLAGS  = -pipe -Wall -O3 -fomit-frame-pointer -fopenmp -pthread -march=$(ARCH) -lm
CXXFLAGS = $(CCFLAGS)

# Targets
FILES    := $(wildcard */*.c) $(wildcard */*.cpp) $(wildcard */*.rs)
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

.PHONY: default bench-prep bench bench-test clean clean-benches clean-all

default: $(BINARIES)
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
	$(CC) $(CCFLAGS) -fno-tree-vectorize $< -o $@
%.cpp.run: %.cpp
	$(CXX) $(CXXFLAGS) -fno-tree-vectorize $< -o $@

%.c.simd.run: %.c
	$(CC) $(CCFLAGS) $< -o $@
%.cpp.simd.run: %.cpp
	$(CXX) $(CXXFLAGS) $< -o $@


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
