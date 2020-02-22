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

.PHONY: default bench bench-test freq clean clean-benches clean-all

default: $(BINARIES)

freq:
	sudo ./adjust-cpu-freq.sh $(FREQ)

# Benchmark settings
NBODY    := 50000000
REVCOMP  := 25000000
FASTA    := 25000000
TREES    := 21
SPECTRAL := 5500
BM_OUT = $@

# Set a timeout of 15 min
TIMEOUT_SECS := 900
TIMEOUT := timeout -s KILL $(TIMEOUT_SECS)

# Adjust cpu frequencies then run benchmarks
bench: freq $(BENCHES)

# Reduced settings for testing
bench-test: NBODY    := 1000
bench-test: REVCOMP  := 1000
bench-test: FASTA    := 1000
bench-test: TREES    := 10
bench-test: SPECTRAL := 100

bench-test: BM_OUT := -
bench-test: TIMEOUT :=
bench-test: bench

# Always run benchmarks
.FORCE:

# Special rule for benchmarking utility
bencher: bencher.c cpufreq.h fileutils.h
	$(CC) -g $(CCFLAGS) -DISA_NAME="\"$(MACHINE)\"" $< -o $@

# Compile benchmarks
%.c.run: %.c
	$(CC) $(CCFLAGS) $< -o $@

%.cpp.run: %.cpp
	$(CXX) $(CXXFLAGS) $< -o $@

# Run benchmarks
.SECONDEXPANSION: # Adapt diff filenames
nbody/%.bm: nbody/%.run output/nbody-$$(NBODY).txt bencher .FORCE
	-$(TIMEOUT) ./bencher -diff output/nbody-$(NBODY).txt -abserr 1.0e-8 $(BM_OUT) $< $(NBODY)

revcomp/%.bm: revcomp/%.run output/fasta-$$(REVCOMP).txt output/revcomp-$$(REVCOMP).txt bencher .FORCE
	-$(TIMEOUT) ./bencher -i output/fasta-$(REVCOMP).txt -diff output/revcomp-$(REVCOMP).txt $(BM_OUT) $< 0

trees/%.bm: trees/%.run output/trees-$$(TREES).txt bencher .FORCE
	-$(TIMEOUT) ./bencher -diff output/trees-$(TREES).txt $(BM_OUT) $< $(TREES)

spectral/%.bm: spectral/%.run output/spectral-$$(SPECTRAL).txt bencher .FORCE
	-$(TIMEOUT) ./bencher -diff output/spectral-$(SPECTRAL).txt $(BM_OUT) $< $(SPECTRAL)

fasta/%.bm: fasta/%.run output/fasta-$$(FASTA).txt bencher .FORCE
	-$(TIMEOUT) ./bencher -diff output/fasta-$(FASTA).txt $(BM_OUT) $< $(FASTA)

# Clean up
clean:
	@-rm -f bencher
	@-rm -f */*.run
	@-rm -rf output

clean-benches:
	@-rm -f */*.bm

clean-all: clean clean-benches

.SECONDARY: # Keep diff files
output/nbody-%.txt: nbody/1.c.run
	@mkdir -p output
	./$< $* > $@

output/revcomp-%.txt: revcomp/2.c.run output/fasta-%.txt
	@mkdir -p output
	cat output/fasta-$*.txt | ./$< 0 > $@

output/trees-%.txt: trees/1.c.run
	@mkdir -p output
	./$< $* > $@

output/spectral-%.txt: spectral/1.c.run
	@mkdir -p output
	./$< $* > $@

output/fasta-%.txt: fasta/1.c.run
	@mkdir -p output
	./$< $* > $@
