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

default: $(BINARIES)
bench: $(BENCHES)

# Benchmark settings
NBODY    := 50000000
REVCOMP  := revcomp-input100000000.txt # TODO bigger input
FASTA    := 25000000
TREES    := 21
SPECTRAL := 5500
BM_OUT = $@

bench-test: NBODY    := 1000
bench-test: REVCOMP  := revcomp-input100000000.txt
bench-test: FASTA    := 1000
bench-test: TREES    := 10
bench-test: SPECTRAL := 100

bench-test: BM_OUT := -
bench-test: bench

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
nbody/%.bm: nbody/%.run bencher .FORCE
	./bencher $(BM_OUT) $< $(NBODY)

revcomp/%.bm: revcomp/%.run bencher .FORCE
	./bencher -i $(REVCOMP) $(BM_OUT) $< 0

fasta/%.bm: fasta/%.run bencher .FORCE
	./bencher $(BM_OUT) $< $(FASTA)

trees/%.bm: trees/%.run bencher .FORCE
	./bencher $(BM_OUT) $< $(TREES)

spectral/%.bm: spectral/%.run bencher .FORCE
	./bencher $(BM_OUT) $< $(SPECTRAL)

# Clean up
clean:
	@-rm -f bencher
	@-rm -f */*.run
	@-rm -f */*.bm
