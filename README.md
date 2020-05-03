# Benchmarks
Repository for benchmarking different systems using programs from the [Computer Language Benchmarks Game](https://benchmarksgame-team.pages.debian.net/benchmarksgame/).

## Tour
This project contains the following directories:
- **bencher**&emsp;C-binary which runs and times benchmark programs (see [Benchmark Procedure](#benchmark-procedure))
- **benchmarks**&emsp;Files related to benchmark programs, split into directories of different benchmark types (see [Selecting Programs](#selecting-programs), [Compiling](#compiling), [Benchmarking](#benchmarking))
- **cargo**&emsp;Empty cargo project used to compile dependencies (see [Rust](#rust))
- **output**&emsp;Will contain the bencher binary as well as files to diff program output against (see [Benchmark Procedure](#benchmark-procedure))
- **plots**&emsp;Scripts related to making plots using [gnuplot](http://www.gnuplot.info/) (see [Plotting](#plotting))
- **scripts**&emsp;Various utility scripts (see [Selecting Programs](#selecting-programs), [Rust](#rust), [Benchmark Procedure](#benchmark-procedure))
- **tmp**&emsp;Mounting directory for a tmpfs file-system to hold program output during benchmark runs (see [Benchmark Procedure](#benchmark-procedure))

## Setup
All setup steps are currently tracked in the repository, configured for the HiFive Freedom Unleashed and the RaspberryPi 4B.

### Selecting Programs
Programs are selected from the extracted [zip of all programs](https://salsa.debian.org/benchmarksgame-team/benchmarksgame#what-else) using `script/extract.lua`.

1. Edit the `dirs` table to change how benchmark names are mapped
2. Edit the `c_exclude` and `rs_exclude` tables to blacklist [patterns](https://www.lua.org/manual/5.3/manual.html#6.4.1) that may not work in your testing environments (usually include / use statements)
3. Run `lua script/extract.lua <path-to-project-root> <path-to-extracted-zip>/*/*`

### Rust
To setup Rust compilation run: `lua script/update_cargo.sh`

This will setup the `cargo` directory, which contains an empty rust binary project. Compiling this project will download and compile all dependencies collected before.

The Makefile will automatically compile this project for all target platforms as needed, as well as storing the correct `rustc` parameters. This allows running all Rust program builds in parallel.


## Compiling
The default make target will compile all benchmarks for your current system. This one should be run in parallel: `make -j <number-of-cores>`. Individual files can be requested by running `make benchmarks/<type>/<number>.<lang>.run`.

### Cross-compilation
The Makefile is currently set-up to cross-compile Rust sources for the following targets:
- `riscv64gc-unknown-linux-gnu`
- `armv7-unknown-linux-gnueabihf`

On systems which correspond to these, the Makefile will look for `$(uname -m).run.tar.gz` in the project root and extract executables as required.

Tarballs can either be requested individually by running `make <target-uname-m>.run.tar.gz` or for all available targets at once using the `cross` make target. This step can also run in parallel (see [Compiling](#compiling)).

## Benchmarking
Benchmarks are usually run using the `bench` make target (should not be parallelized). They can also be requested individually by running `make benchmarks/<type>/<number>.<lang>.bm`

The make target `bench-test` is available to run all benchmarks with reduced inputs, which allows testing all program binaries for functionality.

### Benchmark procedure
The `bencher` binary is responsible for most of the benchmark procedure. It will go through the following steps for each program:
1. Ensure proper CPU scaling setup
  - For `userspace` governor: denotes target frequency
  - For `performance` governor: denotes max frequency
  - Other governors result in an error
2. Run the benchmark 5 times
  1. Run the program
    - Pin to CPU 1 using `sched_setaffinity`
    - Use `setrlimit` for timeout if applicable
    - Use pipe to deliver input data if applicable
    - Map `stdout` of program to buffer file in tmpfs (created in Makefile)
  2. Get runtime and resource data
    - Use `clock_gettime` for precise timing
    - Use `wait4` (`getrusage`) for additional information
    - Write data in CSV format
  3. Check output against baseline (in `output` directory, created in Makefile)
    - Textual diff
    - Numerical diff (with absolute error)
    - Planned: Binary diff

## Plotting
The scripts in the `plots` directory process and plot the raw data collected in [benchmarking](#benchmarking).

### Plotting setup
The script `plots/prepare.lua` will work with paths in the format `<platform>/<type>/<number>.<lang>.bm`.

These can be set up by extracting the tarballs generated from `make pack` (in the project root) inside `plots/<platform-name>`. The platform name is arbitrary, but will show up in the plots.

The default make target (in the `plots` directory) will then generate plots for the `total` column

### Data collection
The `plots/prepare.lua` script should be called from the `plots` directory using `lua prepare.lua <column> */*/*.bm`. It performs the following steps:

1. Collect values in the requested column
2. Normalize to 1 GHz
3. Calculate geometric mean and standard deviation per program
  - Store in `output/data/<type>.dat`
4. Calculate geometric mean and minimum per benchmark type
  - Store in `output/data/combined.dat`

Geometric mean is used, as it works correctly with normalized values (see [Flemming and Wallace](plots/paper4.pdf)).

### Gnuplot script
The script `plots/all.plt` will create PDF plots for all benchmark types (currently hard-coded), as well as `output/plots/average.pdf` and `output/plots/fastest.pdf` from `output/data/combined.dat`. The raw data can be found in the [plots](../plots) branch.

## Results
The following plots show benchmark results for the HiFive Freedom Unleashed (`riscv`) and the Raspberry Pi 4 Model B (`pi`). The compiler versions are `9.1.0` for the HiFive and `8.3.0` for the Pi.

### Average
Average total program time, normalized to 1 GHz.
![Average](../plots/average.png?raw=true)

### Fastest
Fastest total program time, normalized to 1 GHz.
![Fastest](../plots/fastest.png?raw=true)
