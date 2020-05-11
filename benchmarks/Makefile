DATA := $(wildcard */*.bm)

.PHONY: all clean

# Pack bechmark results
all: $(DATA) compiler_info.txt
	tar -czvf ../$(NODE)_$(shell date -I).tar.gz $(DATA) compiler_info.txt
	rm compiler_info.txt

# Collect compiler versions
compiler_info.txt: .FORCE
	@$(CC) --version | head -n 1 > $@
	@$(CXX) --version | head -n 1 >> $@
