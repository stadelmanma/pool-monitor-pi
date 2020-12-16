#!/bin/sh
#
# The actual values for following variables should be set by the env file
# in the service script:
# sensor1_uuid="28-011937c85701"
# sensor1_name="air"
# sensor2_uuid="28-01193804ca0b"
# sensor2_name="water"
# temperature_db="temperature-readings.db"
# html_template="template.html"
# output_path="/var/www/html"
# interval=60
# b2_bucket=temperature-monitoring
set -eu

w1_dir="/sys/bus/w1/devices"
counter_file="temperature-monitor.counter"


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
    gnuplot -e "sensor1_name='$sensor1_name';sensor2_name='$sensor2_name';xaxis_fmt='$4'" temperature-plot.plt
}


# read counter so we can trigger specific events, if the file doesn't
# exist set counter to 0
if [ ! -f "$counter_file" ]; then
    counter='0'
    echo "No counter file found at '$counter_file', setting counter=0"
else
    counter=$(cat "$counter_file")
fi
echo $(($counter + $interval )) >  "$counter_file"


# take readings
temp="$(read_temperature $sensor1_uuid)"
sensor1_tempf=$(awk "BEGIN {print $temp*1.8 + 32}")
timestamp="$(date '+%Y-%m-%d %H:%M:%S %Z')"
save_temperature "$sensor1_uuid" "$sensor1_name" "$timestamp" "$temp"
echo "Saved $sensor1_name temperature reading of ${temp}C at $timestamp"

temp="$(read_temperature $sensor2_uuid)"
sensor2_tempf=$(awk "BEGIN {print $temp*1.8 + 32}")
timestamp="$(date '+%Y-%m-%d %H:%M:%S %Z')"
save_temperature "$sensor2_uuid" "$sensor2_name" "$timestamp" "$temp"
echo "Saved $sensor2_name temperature reading of ${temp}C at $timestamp"


# regenerate plots, this is expensive so we don't do it every time
if [ -z $(($counter % 300)) ]; then  # 5 minutes
    echo "Recreating 24h plot..."
    plot_data "$(date -d "$(date) - 24 hours" '+%Y-%m-%d %H:%M:%S %Z')" 10 2 '%m/%d %H:%M' > "$output_path/temperature-24h.png"
fi
if [ -z $(($counter % 3600)) ]; then  # 1 hour
    echo "Recreating 7d plot..."
    plot_data "$(date -d "$(date) - 7 days" '+%Y-%m-%d %H:%M:%S %Z')" 20 5 '%m/%d' > "$output_path/temperature-7d.png"
    echo "Uploading 7d plot to B2 bucket '$b2_bucket'..."
    ~/.local/bin/b2 upload-file "$b2_bucket" "$output_path/temperature-7d.png" temperature-7d.png
fi
if [ -z $(($counter % 21600)) ]; then  # 6 hours
    echo "Recreating 1y plot..."
    plot_data "$(date -d "$(date) - 1 year" '+%Y-%m-%d %H:%M:%S %Z')" 100 10 '%m/%d' > "$output_path/temperature-1y.png"
    echo "Uploading 1y plot to B2 bucket '$b2_bucket'..."
    ~/.local/bin/b2 upload-file "$b2_bucket" "$output_path/temperature-1y.png" temperature-1y.png
fi


# regenerate template
sed "s/%timestamp%/$timestamp/" "$html_template" | \
sed "s/%sensor1_name%/$sensor1_name/" | \
sed "s/%sensor1_temp%/$sensor1_tempf/" | \
sed "s/%sensor2_name%/$sensor2_name/" | \
sed "s/%sensor2_temp%/$sensor2_tempf/" > "$output_path/index.html"

if [ -z $(($counter % 900)) ]; then  # 15 minutes
    echo "Recreating 1y plot..."
    plot_data "$(date -d "$(date) - 1 year" '+%Y-%m-%d %H:%M:%S %Z')" 100 10 '%m/%d' > "$output_path/temperature-1y.png"
    echo "Uploading 24h plot and HTML page to B2 bucket '$b2_bucket'..."
    ~/.local/bin/b2 upload-file "$b2_bucket" "$output_path/index.html" temperature.html
    ~/.local/bin/b2 upload-file "$b2_bucket" "$output_path/temperature-24h.png" temperature-24h.png
fi
