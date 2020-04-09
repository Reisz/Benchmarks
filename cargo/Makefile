CARGO := cargo build
CARGO_FLAGS := --release

target/%: Cargo.toml Cargo.lock
	touch src/main.rs
	mkdir -p target
	RUSTFLAGS="$(RCFLAGS)" $(CARGO) $(CARGO_FLAGS) -v  2>&1 | rg -r '$$1' '\s+Running `rustc --crate-name main.*?(-L [^`]+)`' > $@
