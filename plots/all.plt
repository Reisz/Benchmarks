set terminal pdf enhanced background rgb "white"

set border 3 linewidth .3
set xtics border nomirror norotate
set ytics border nomirror norotate

set style fill solid border rgb "black"

set style data histogram
set style histogram errorbars lw 2

set ylabel "seconds"

set output "output/plots/fannkuch.pdf"
plot for [COL=2:4:2] 'output/data/fannkuch.dat' using COL:COL+1:xtic(1) title col

set output "output/plots/fasta.pdf"
plot for [COL=2:4:2] 'output/data/fasta.dat' using COL:COL+1:xtic(1) title col

set output "output/plots/knucleotide.pdf"
plot for [COL=2:4:2] 'output/data/knucleotide.dat' using COL:COL+1:xtic(1) title col

set output "output/plots/mandelbrot.pdf"
plot for [COL=2:4:2] 'output/data/mandelbrot.dat' using COL:COL+1:xtic(1) title col

set output "output/plots/nbody.pdf"
plot for [COL=2:4:2] 'output/data/nbody.dat' using COL:COL+1:xtic(1) title col

set output "output/plots/pi.pdf"
plot for [COL=2:4:2] 'output/data/pi.dat' using COL:COL+1:xtic(1) title col

set output "output/plots/regex.pdf"
plot for [COL=2:4:2] 'output/data/regex.dat' using COL:COL+1:xtic(1) title col

set output "output/plots/revcomp.pdf"
plot for [COL=2:4:2] 'output/data/revcomp.dat' using COL:COL+1:xtic(1) title col

set output "output/plots/spectral.pdf"
plot for [COL=2:4:2] 'output/data/spectral.dat' using COL:COL+1:xtic(1) title col

set output "output/plots/trees.pdf"
plot for [COL=2:4:2] 'output/data/trees.dat' using COL:COL+1:xtic(1) title col

set style histogram clustered
set yrange [0:300]

set output "output/plots/average.pdf"
plot for [COL=2:4:2] 'output/data/combined.dat' using COL:xtic(1) title col

set output "output/plots/fastest.pdf"
plot for [COL=3:5:2] 'output/data/combined.dat' using COL:xtic(1) title col
