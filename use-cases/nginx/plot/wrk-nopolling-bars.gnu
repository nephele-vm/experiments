set datafile separator ','

set key left top
set xlabel "# Workers"
set ylabel "Requests/sec"

set term pdf
set output output1

#set style fill solid
#set boxwidth 0.8
#set yrange [0:*]
#unset key
#
#plot filename1 using 0:2:xtic(1) with boxes, \
#     '' using 0:2:3:4 with yerrorbars lc rgb 'black' pt 1 lw 1


set xrange [-0.5:] #custom adjust
set xtics offset 1.4

set yrange [0:]
set style fill solid 0.5
set style histogram errorbars gap 2 lw 1
plot filename1 using 2:3:4:xticlabels(1) w hist t "nginx processes", \
     filename2 using 2:3:4:xticlabels(1) w hist t "nginx clones"


#plot filename1 using 1:2 w l t "1 worker", \
#     filename1 using 1:3 w l t "2 workers", \
#     filename1 using 1:4 w l t "3 workers", \
#     filename1 using 1:5 w l t "4 workers"
