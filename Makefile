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
	./bencher $@ $< 1000

revcomp/%.bm: revcomp/%.run .FORCE
	./bencher -i revcomp-input100000000.txt $@ $< 0

# Clean up
clean:
	@-rm -f bencher
	@-rm -f */*.run
	@-rm -f */*.bm
