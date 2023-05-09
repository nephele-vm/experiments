set datafile separator ';'

set key right top
set xlabel "# of instances"
set ylabel "Free Memory (GB)"

set term pdf
set output output1

# (1) Timestamp
# (6) Free: 2=total, 3=used, 4=free, 5=shared, 6=buff/cache, 7=available
# (4) xl info | grep memory: 8=total, 9=free, 10=shared free, 11=shared used
# 1603537438.690094641;429052;36456;340604;60;51992;379060;1023;491;0;0

plot filename1 using ($4 / 1e6) w l t "Booting Dom0 free" lw 2, \
     filename1 using ($9  / 1000)         w l t "Booting Hyp free", \
     filename2 using ($4 / 1e6) w l t "Cloning Dom0 free" linecolor rgb "web-blue", \
     filename2 using ($9 / 1000)           w l t "Cloning Hyp free"

