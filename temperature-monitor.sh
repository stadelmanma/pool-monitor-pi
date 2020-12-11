#!/bin/sh
set -e

w1_dir="/sys/bus/w1/devices"
sensor1_uuid="28-011937c85701"
sensor1_name="air"
sensor2_uuid="28-01193804ca0b"
sensor2_name="water"
temperature_db="/home/mstadelman/temperature-readings.db"
html_template="/home/mstadelman/pool-monitor-pi/template.html"
interval=60


read_temperature() {
    # Reads a temperature value from the sensor's data bus
    #
    # args: sensor_uuid
    # output: temperature in degC
    cat "$w1_dir/$1/w1_slave"  | tail -n1 | awk -F '=' '{print $2/1000}'
}


save_temperature() {
    # Saves a temperature value and it's associated data in the database
    #
    # args: sensor_uuid, sensor_name, timestamp, temp
    # output: none
    sqlite3 "$temperature_db"  "insert into readings (source_uuid, source_name, timestamp, temperature) values ('$1', '$2', '$3', $4);"
}

select_data() {
    # Select data based on the timestamp and process it into CSV format
    #
    # args: sensor_name, timestamp, N(items) in window, S(tride) between datum
    # output: comma delimited temperature data: timestamp, sensor_name, degF
    sqlite3 "$temperature_db" "select timestamp, source_name, temperature from readings where source_name=\"$1\" and timestamp > \"$2\";" | sed 's/ E[DS]T//g' | awk -F '|' -vn=$3 -vs=$4 -f process_sql_data.awk
}

plot_data() {
    # Generate the PNG plot image of the data from each sensor over the
    # specified time range.
    #
    # args: timestamp, N(items) in window, S(tride) between datum
    # output: PNG formatted plot image
    select_data "$sensor1_name" "$1" $2 $3 > "$sensor1_name.csv"
    select_data "$sensor2_name" "$1" $2 $3 > "$sensor2_name.csv"
    gnuplot -e "sensor1_name='$sensor1_name';sensor2_name='$sensor2_name'" temperature-plot.plt
}

while true
do
    # take readings
    temp="$(read_temperature $sensor1_uuid)"
    sensor1_tempf=$(awk "BEGIN {print $temp*1.8 + 32}")
    timestamp="$(date '+%Y-%m-%d %H:%M:%S %Z')"
    save_temperature "$sensor1_uuid" "$sensor1_name" "$timestamp" "$temp"
    echo "Saved $sensor1_name temperature reading of $temp at $timestamp"

    temp="$(read_temperature $sensor2_uuid)"
    sensor2_tempf=$(awk "BEGIN {print $temp*1.8 + 32}")
    timestamp="$(date '+%Y-%m-%d %H:%M:%S %Z')"
    save_temperature "$sensor2_uuid" "$sensor2_name" "$timestamp" "$temp"
    echo "Saved $sensor2_name temperature reading of $temp at $timestamp"

    # rengerate plot
    plot_data "$(date -d "$(date) - 24 hours" '+%Y-%m-%d %H:%M:%S %Z')" 10 2 > temperature-24h.png
    plot_data "$(date -d "$(date) - 7 days" '+%Y-%m-%d %H:%M:%S %Z')" 20 5 > temperature-7d.png
    plot_data "$(date -d "$(date) - 1 year" '+%Y-%m-%d %H:%M:%S %Z')" 100 10 > temperature-1y.png


    # regenerate template
    sed "s/%timestamp%/$timestamp/" "$html_template" | \
	sed "s/%sensor1_name%/$sensor1_name/" | \
	sed "s/%sensor1_temp%/$sensor1_tempf/" | \
	sed "s/%sensor2_name%/$sensor2_name/" | \
	sed "s/%sensor2_temp%/$sensor2_tempf/" > /var/www/html/index.html

    # wait so many seconds until next reading
    sleep $interval
done
