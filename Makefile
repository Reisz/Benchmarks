# Change flags based on node/machine
NODE := $(shell uname -n)
MACHINE := $(shell uname -m)
ifeq "$(NODE)" "freedom-u540"
	ARCH := -march=rv64gc
	FREQ := 999999
else
	ARCH := -march=native
endif

# Compilers and flags
CC  := gcc
CXX := g++
CCFLAGS  := -pipe -Wall -O3 -fomit-frame-pointer -fopenmp -pthread $(ARCH) -lm
CXXFLAGS := $(CCFLAGS)

# Targets
FILES    := $(wildcard */*.c) $(wildcard */*.cpp) $(wildcard */*.rs)
BINARIES := $(addsuffix .run, $(FILES))
BENCHES  := $(addsuffix .bm, $(FILES))

.PHONY: default bench bench-test freq clean

default: $(BINARIES)

freq:
	sudo ./adjust-cpu-freq.sh $(FREQ)

# Benchmark settings
NBODY    := 50000000
REVCOMP  := revcomp-input100000000.txt # TODO bigger input
FASTA    := 25000000
TREES    := 21
SPECTRAL := 5500
BM_OUT = $@

# Adjust cpu frequencies then run benchmarks
bench: freq $(BENCHES)

# Reduced settings for testing
bench-test: NBODY    := 1000
bench-test: REVCOMP  := revcomp-input100000000.txt
bench-test: FASTA    := 1000
bench-test: TREES    := 10
bench-test: SPECTRAL := 100

bench-test: BM_OUT := -
bench-test: bench

# Set a timeout of 15 min
TIMEOUT_SECS := 900
TIMEOUT := timeout -s KILL $(TIMEOUT_SECS)

# Always run benchmarks
.FORCE:

# Special rule for benchmarking utility
bencher: bencher.c cpufreq.h fileutils.h
	$(CC) $(CCFLAGS) -DISA_NAME="\"$(MACHINE)\" $< -o $@

# Compile benchmarks
%.c.run: %.c
	$(CC) $(CCFLAGS) $< -o $@

%.cpp.run: %.cpp
	$(CXX) $(CXXFLAGS) $< -o $@

# Run benchmarks
nbody/%.bm: nbody/%.run bencher .FORCE
	-$(TIMEOUT) ./bencher $(BM_OUT) $< $(NBODY)

revcomp/%.bm: revcomp/%.run bencher .FORCE
	-$(TIMEOUT) ./bencher -i $(REVCOMP) $(BM_OUT) $< 0

fasta/%.bm: fasta/%.run bencher .FORCE
	-$(TIMEOUT) ./bencher $(BM_OUT) $< $(FASTA)

trees/%.bm: trees/%.run bencher .FORCE
	-$(TIMEOUT) ./bencher $(BM_OUT) $< $(TREES)

spectral/%.bm: spectral/%.run bencher .FORCE
	-$(TIMEOUT) ./bencher $(BM_OUT) $< $(SPECTRAL)

# Clean up
clean:
	@-rm -f bencher
	@-rm -f */*.run
	@-rm -f */*.bm
