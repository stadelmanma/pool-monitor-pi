set terminal png
set xdata time
set datafile separator ","
set timefmt '%Y-%m-%d %H:%M:%S'
set title "Temperature Log"
set xlabel "Time"
set format x xaxis_fmt
set xtics rotate by 45 right nomirror
set ylabel "Temperature"
set key top right

plot sensor1_name.'.csv'  using 1:3 with lines title sensor1_name, sensor2_name.'.csv' using 1:3 with lines title sensor2_name
