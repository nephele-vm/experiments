set datafile separator ' '

set key right bottom
set term pdf
set output output1
set xrange [:300]
set xlabel "Time elapsed (s)"
set ylabel "Throughput (executions/s)"

plot filename1 using 1:2 w l t "Unikraft baseline (KFX+AFL)", \
     filename2 using 1:2 w l t "Unikraft (KFX+AFL)", \
     filename3 using 1:2 w l t "Unikraft+cloning baseline (KFX+AFL)", \
     filename4 using 1:2 w l t "Unikraft+cloning (KFX+AFL)", \
     filename5 using 1:2 w l t "Linux process baseline (AFL)", \
     filename6 using 1:2 w l t "Linux process (AFL)", \
     filename7 using 1:2 w l t "Linux kernel module baseline (KFX+AFL)"

