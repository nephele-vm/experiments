set datafile separator ';'

set key left top
set xlabel "# of instances"
set ylabel "Milliseconds"
set term pdf
set output output1

plot filename1 using 1 w l t "boot" \
   , filename2 using 1 w l t "restore" \
   , filename3 using 3 w l t "clone + XS deep copy" \
   , filename4 using 3 w l t "clone"

