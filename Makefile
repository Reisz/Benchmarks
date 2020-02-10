# Node based flags
U540 := -march=rv64gc

# Change flags based on node
NODE := $(shell uname -n)
ifeq "$(NODE)" "freedom-u540"
	ARCH := $(U540)
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

.PHONY: default bench clean

default: bencher $(BINARIES)
bench: bencher $(BENCHES)

# Benchmark settings
NBODY    := 50000000
REVCOMP  := revcomp-input100000000.txt # TODO bigger input
FASTA    := 25000000
TREES    := 21
SPECTRAL := 5500

# Always run benchmarks
.FORCE:

# Special rule for benchmarking utility
bencher: bencher.c
	$(CC) $(CCFLAGS) $< -o $@

# Compile benchmarks
%.c.run: %.c
	$(CC) $(CCFLAGS) $< -o $@

%.cpp.run: %.cpp
	$(CXX) $(CXXFLAGS) $< -o $@

# Run benchmarks
nbody/%.bm: nbody/%.run .FORCE
	./bencher $@ $< $(NBODY)

revcomp/%.bm: revcomp/%.run .FORCE
	./bencher -i $(REVCOMP) $@ $< 0

fasta/%.bm: fasta/%.run .FORCE
	./bencher $@ $< $(FASTA)

trees/%.bm: trees/%.run .FORCE
	./bencher $@ $< $(TREES)

spectral/%.bm: spectral/%.run .FORCE
	./bencher $@ $< $(SPECTRAL)

# Clean up
clean:
	@-rm -f bencher
	@-rm -f */*.run
	@-rm -f */*.bm
