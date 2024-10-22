# Benchmarks
Repository for benchmarking different systems using programs from the [Computer Language Benchmarks Game](https://benchmarksgame-team.pages.debian.net/benchmarksgame/).

## Tour
This project contains the following directories:
- **bencher**&emsp;C-binary which runs and times benchmark programs (see [Benchmark Procedure](#benchmark-procedure))
- **benchmarks**&emsp;Files related to benchmark programs, split into directories of different benchmark types (see [Selecting Programs](#selecting-programs), [Compiling](#compiling), [Benchmarking](#benchmarking))
- **cargo**&emsp;Empty cargo project used to compile dependencies (see [Rust](#rust))
- **output**&emsp;Will contain the bencher binary as well as files to diff program output against (see [Benchmark Procedure](#benchmark-procedure))
- **plots**&emsp;Scripts related to making plots using [gnuplot](http://www.gnuplot.info/) (see [Plotting](#plotting))
- **scripts**&emsp;Various utility scripts (see [Selecting Programs](#selecting-programs), [Rust](#rust), [Benchmark Procedure](#benchmark-procedure), [iPerf](#iperf))
- **tmp**&emsp;Mounting directory for a tmpfs file-system to hold program output during benchmark runs (see [Benchmark Procedure](#benchmark-procedure))

## Hardware
These benchmarks exist to evaluate the performance of the [HiFive Unleashed](https://www.sifive.com/boards/hifive-unleashed) developer board for the [Freedom U540 SoC](https://www.sifive.com/chip-designer#fu540). A [Raspberry Pi 4B](https://www.raspberrypi.org/products/raspberry-pi-4-model-b/) is used as a baseline for the measurements.

### HiFive Unleashed
The Freedom U540 SoC has 4 `RV64GC` application cores and 1 `RV64IMAC` management core. Each application core contains 32 KiB each of instruction and data cache, while the management core uses 16 KiB instruction cache and 8 KiB of tightly integrated memory. 2 MB of L2 cache then connect to 8 GB of DDR4 ram. All of these memory layers also use ECC.

Operating system and programs are stored on a Micro-SD card.

### Raspberry Pi 4B
The BCM2711 on the Raspberry Pi has 4 ARM Cortex-A72 cores. They each contain 48 KiB of instruction cache and 32 KiB of data cache. 1 MB of L2 cache then connects to 4 GB of LPDDR4 ram.

Operating system and programs are stored on a Micro-SD card.

## Setup
Some files in this repository are a result of executing the following steps. These files are currently configured for the HiFive Freedom Unleashed and the RaspberryPi 4B.

### Selecting Programs
Programs are selected from the extracted [zip of all programs](https://salsa.debian.org/benchmarksgame-team/benchmarksgame#what-else) using `script/extract.lua`.

1. Edit the `dirs` table to change how benchmark names are mapped
2. Edit the `c_exclude` and `rs_exclude` tables to blacklist [patterns](https://www.lua.org/manual/5.3/manual.html#6.4.1) that may not work in your testing environments (usually include / use statements)
3. Run `lua script/extract.lua <path-to-benchmarks-directory> <path-to-extracted-zip>/*/*`

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

### SIMD Benchmarks
The Makefile also contains facilities to disable vectorization during compilation. This was intended to allow fair comparison to platforms that do not support such instructions (for example RISC-V). However, the current efforts to turn of vectorization did not result in a significant change in benchmark runtime.

#### SIMD Benchmark Procedure
By default, the Makefile contains the variable `SIMD`, which can be unset for platforms that do not support vector instructions.

If this variable is set, the Makefile will duplicate all the target programs with an additional `.simd` suffix. During compilation, files with the `.run.simd` suffix will be compiled using the regular argument set, while compilation for files just ending in `.run` will have an additional `-fno-tree-vectorize` argument.

The benchmarking implementation will change the bencher command for `.simd` files to include an if statement which prevents benchmarking in case the flag did not change the resulting binary executable.

### Benchmark Procedure
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

### iPerf
This repository also contains utilities to facilitate a comparison between [ethox-iperf](https://github.com/HeroicKatora/ethox) and [iPerf3](https://iperf.fr/). The setup is intended for testing between two nodes, which are directly connected via a switch.

To get the measurements, use `./scripts/iperf-helper.sh <ethox-iperf-executable> <device> <target-ip> benchmarks/iperf-<target-name>.log [client]`. Run two instances at the same time, but only one having the `client` argument. Always start the instance without the client argument first. `<target-name>` needs to correspond to the directory names used in the [Plotting Setup](#plotting-setup).

**Example**
1. Node 1: `./scripts/iperf-helper.sh "sudo ./iperf3" eth0 192.168.0.102/24 benchmarks/iperf-node2.log`
2. Node 2: `./scripts/iperf-helper.sh ./iperf3 eth1 192.168.0.101/24 benchmarks/iperf-node1.log client`

## Plotting
The scripts in the `plots` directory process and plot the raw data collected in [benchmarking](#benchmarking).

### Plotting setup
The script `plots/prepare.lua` will work with benchmark results in the format `<platform>/<type>/<number>.<lang>.bm` and [iPerf](#iperf) logs as `<platform>/iperf-<target-name>.log`.

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
The script `plots/all.plt` will create PDF plots for all benchmark types (currently hard-coded), as well as `output/plots/average.pdf` and `output/plots/fastest.pdf` from `output/data/combined.dat` and `output/plots/iperf.pdf` from `output/data/iperf.dat`.

## Results
The following plots show benchmark results for the HiFive Freedom Unleashed (`riscv`) and the Raspberry Pi 4 Model B (`pi`). The compiler versions are `9.1.0` for the HiFive and `8.3.0` for the Pi.

The raw data can be found in the [plots](../../tree/plots) branch.

### Average
Average total program time, normalized to 1 GHz.
![Average](../plots/average.png?raw=true)

### Fastest
Fastest total program time, normalized to 1 GHz.
![Fastest](../plots/fastest.png?raw=true)
