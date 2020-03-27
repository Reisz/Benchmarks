# Use -march=native by default
ARCH := native

# Change flags based on node/machine
NODE := $(shell uname -n)
MACHINE := $(shell uname -m)
ifeq "$(NODE)" "freedom-u540"
	ARCH := rv64gc
	FREQ := 999999
else ifeq "$(NODE)" "raspberrypi"
	FREQ := 1
endif

# Compilers and flags
CC  := gcc
CXX := g++
CCFLAGS  := -pipe -Wall -O3 -fomit-frame-pointer -fopenmp -pthread -march=$(ARCH) -lm
CXXFLAGS := $(CCFLAGS)

# Targets
FILES    := $(wildcard */*.c) $(wildcard */*.cpp) $(wildcard */*.rs)
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

# Set a timeout of 20 min
TIMEOUT_SECS := 1200
TIMEOUT := timeout -s KILL $(TIMEOUT_SECS)

.PHONY: default bench-prep bench bench-test clean clean-benches clean-all

default: $(BINARIES)

bench-prep:
	mkdir -p $(TMP_DIR)
	sudo mount -t tmpfs tmpfs $(TMP_DIR)
	sudo ./adjust-cpu-freq.sh $(FREQ)

# Adjust cpu frequencies then run benchmarks
bench: bench-prep $(BENCHES)

# Reduced settings for testing
bench-test: FASTA    := 1000
bench-test: NBODY    := 1000
bench-test: REVCOMP  := 1000
bench-test: SPECTRAL := 100
bench-test: TREES    := 10

bench-test: BM_OUT := -
bench-test: TIMEOUT :=
bench-test: bench

# Always run benchmarks
.FORCE:

# Special rule for benchmarking utility
bencher: bencher.c cpufreq.h fileutils.h
	$(CC) -g $(CCFLAGS) -DISA_NAME='"$(MACHINE)"' $< -o $@

# Compile benchmark binaries
%.c.run: %.c
	$(CC) $(CCFLAGS) $< -o $@
%.cpp.run: %.cpp
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

# Clean up
clean:
	@-rm -f bencher
	@-rm -f */*.run
clean-benches:
	@-rm -f */*.bm
clean-all: clean clean-benches

# Run benchmarks
.SECONDEXPANSION: # Adapt diff filenames

.SECONDARY: output/fasta-$$(FASTA).txt
fasta/%.bm: fasta/%.run output/fasta-$$(FASTA).txt bencher .FORCE
-$(TIMEOUT) ./bencher -diff output/fasta-$(FASTA).txt $(BM_OUT) $< $(FASTA)

.SECONDARY: output/nbody-$$(NBODY).txt
nbody/%.bm: nbody/%.run output/nbody-$$(NBODY).txt bencher .FORCE
	-$(TIMEOUT) ./bencher -diff output/nbody-$(NBODY).txt -abserr 1.0e-8 $(BM_OUT) $< $(NBODY)

.SECONDARY: output/fasta-$$(REVCOMP).txt output/revcomp-$$(REVCOMP).txt
revcomp/%.bm: revcomp/%.run output/fasta-$$(REVCOMP).txt output/revcomp-$$(REVCOMP).txt bencher .FORCE
	-$(TIMEOUT) ./bencher -i output/fasta-$(REVCOMP).txt -diff output/revcomp-$(REVCOMP).txt $(BM_OUT) $< 0

.SECONDARY: output/spectral-$$(SPECTRAL).txt
spectral/%.bm: spectral/%.run output/spectral-$$(SPECTRAL).txt bencher .FORCE
	-$(TIMEOUT) ./bencher -diff output/spectral-$(SPECTRAL).txt $(BM_OUT) $< $(SPECTRAL)

.SECONDARY: output/trees-$$(TREES).txt
trees/%.bm: trees/%.run output/trees-$$(TREES).txt bencher .FORCE
	-$(TIMEOUT) ./bencher -diff output/trees-$(TREES).txt $(BM_OUT) $< $(TREES)
