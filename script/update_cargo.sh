head -n $(grep -nF "[dependencies]" cargo/Cargo.toml | cut -f1 -d:) cargo/Cargo.toml > new
mv new cargo/Cargo.toml

for crate in $(rg -NIr "\$1" "^\\s*extern crate ([^;]+);" | sort -u); do
    cargo search $crate | head -n 1 >> cargo/Cargo.toml
done
