DATA := $(wildcard */iperf-*.log) $(wildcard */*/*.bm)

.PHONY: all clean

all: $(DATA)
	@mkdir -p output/data
	lua prepare.lua total $(DATA)
	@mkdir -p output/plots
	gnuplot all.plt

clean:
	@-rm -rf output
