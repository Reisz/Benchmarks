head -n $(grep -nF "[dependencies]" cargo/Cargo.toml | cut -f1 -d:) cargo/Cargo.toml > new
mv new cargo/Cargo.toml

rm cargo/rustc-deps
for crate in $(rg -NIr "\$1" "^\\s*extern crate ([^;]+);" | sort -u); do
    cargo search $crate | head -n 1 >> cargo/Cargo.toml
    printf " --extern $crate=cargo/target/{target}/release/deps/lib$crate-*.rlib" >> cargo/rustc-deps
done
