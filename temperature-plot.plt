set terminal png
set timefmt '%a %b %d %H:%M:%S %Z %Y'
set title "Temperature Log"
set xlabel "Time"
set ylabel "Temperature"

plot sensor1_name.'.dat'  using 1:3 with lines title sensor1_name, sensor2_name.'.dat' using 1:3 with lines title sensor2_name
