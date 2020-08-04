#!/bin/sh
w1_dir="/sys/bus/w1/devices"
sensor1_uuid="28-011937c85701"
sensor1_name="air"
sensor2_uuid="28-01193804ca0b"
sensor2_name="water"
temperature_db="/home/mstadelman/temperature-readings.db"
interval=60


read_temperature() {
    cat "$w1_dir/$1/w1_slave"  | tail -n1 | awk -F '=' '{print $2/1000}'
}


save_temperature() {
    sqlite3 "$temperature_db"  "insert into readings (source_uuid, source_name, timestamp, temperature) values ('$1', '$2', '$3', $4);"
}

select_data() {
    sqlite3 "$temperature_db" "select timestamp, source_name, temperature from readings where source_name='$1';" | sed 's/|/,/g' | awk -F ',' -v n=0 '{print n,$2,$3*1.8+32; n += 1}'
}

while true
do
    # take readings
    temp="$(read_temperature $sensor1_uuid)"
    timestamp="$(date '+%Y-%m-%d %H:%M:%S %Z')"
    save_temperature "$sensor1_uuid" "$sensor1_name" "$timestamp" "$temp"
    echo "Saved $sensor1_name temperature reading of $temp at $timestamp"

    temp="$(read_temperature $sensor2_uuid)"
    timestamp="$(date '+%Y-%m-%d %H:%M:%S %Z')"
    save_temperature "$sensor2_uuid" "$sensor2_name" "$timestamp" "$temp"
    echo "Saved $sensor2_name temperature reading of $temp at $timestamp"

    # rengerate plot
    select_data "$sensor1_name" > "$sensor1_name.dat"
    select_data "$sensor2_name" > "$sensor2_name.dat"
    gnuplot -e "sensor1_name='$sensor1_name';sensor2_name='$sensor2_name'" temperature-plot.plt > temperature.png


    # wait so many seconds until next reading
    sleep $interval
done

