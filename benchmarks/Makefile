DATA := $(wildcard */*.bm) $(wildcard iperf-*.log)

.PHONY: all clean

# Pack bechmark results
all: $(DATA) compiler_info.txt
	tar -czvf ../$(shell uname -n)_$(shell date -I).tar.gz $(DATA) compiler_info.txt
	rm compiler_info.txt

# Collect compiler versions
compiler_info.txt:
	@$(CC) --version | head -n 1 > $@
	@$(CXX) --version | head -n 1 >> $@
