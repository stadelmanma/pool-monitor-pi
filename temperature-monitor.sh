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


echo_err() {
    1>&2 echo "$@"
}


read_sensor() {
    # Reads a temperature value from the sensor's data bus
    #
    # args: sensor_uuid
    # output: temperature in degC, or blank if reading failed
    cat "$w1_dir/$1/w1_slave"  | cut -d= -f 2 | tr -s '\n ' ',' | awk -F, '{if ($2=="YES") print $3/1000}'
}


read_temperature() {
    # Reads a temperature value from the sensor's data bus
    #
    # args: sensor_uuid, max_attempts
    # output: temperature in degC, or blank if reading failed
    temp=""
    attempt=0
    while [ -z "$temp" ] && [ $attempt -lt $2 ]; do
        temp="$(read_sensor $1)"
        attempt=$(($attempt + 1))
        if [ -z "$temp" ]; then
            echo_err "[ERROR] Failed to read temperature for sensor $1 ($attempt/$2 attempts)"
            sleep 1  # sleep for a second to try and let the problem pass
        fi
    done
    echo "$temp"
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
    echo_err "[WARNING] No counter file found at '$counter_file', setting counter=0"
else
    counter=$(cat "$counter_file")
fi
echo $(($counter + $interval )) >  "$counter_file"


# take readings
temp="$(read_temperature $sensor1_uuid 10)"
timestamp="$(date '+%Y-%m-%d %H:%M:%S %Z')"
if [ ! -z "$temp" ]; then
    sensor1_tempf=$(awk "BEGIN {print $temp*1.8 + 32}")
    save_temperature "$sensor1_uuid" "$sensor1_name" "$timestamp" "$temp"
    echo_err "[INFO] Saved $sensor1_name temperature reading of ${temp}C at $timestamp"
else
    sensor1_tempf=""
fi

temp="$(read_temperature $sensor2_uuid 10)"
timestamp="$(date '+%Y-%m-%d %H:%M:%S %Z')"
if [ ! -z "$temp" ]; then
    sensor2_tempf=$(awk "BEGIN {print $temp*1.8 + 32}")
    save_temperature "$sensor2_uuid" "$sensor2_name" "$timestamp" "$temp"
    echo_err "[INFO] Saved $sensor2_name temperature reading of ${temp}C at $timestamp"
else
    sensor2_tempf=""
fi

# regenerate plots, this is expensive so we don't do it every time
if [ "$(($counter % 300))" = "0" ]; then  # 5 minutes
    echo_err "[INFO] Recreating 24h plot..."
    plot_data "$(date -d "$(date) - 24 hours" '+%Y-%m-%d %H:%M:%S %Z')" 10 2 '%m/%d %H:%M' > "$output_path/temperature-24h.png"
fi
if [ "$(($counter % 3600))" = "0" ]; then  # 1 hour
    echo_err "[INFO] Recreating 7d plot..."
    plot_data "$(date -d "$(date) - 7 days" '+%Y-%m-%d %H:%M:%S %Z')" 20 5 '%m/%d' > "$output_path/temperature-7d.png"
    echo_err "[INFO] Uploading 7d plot to B2 bucket '$b2_bucket'..."
    ~/.local/bin/b2 upload-file "$b2_bucket" "$output_path/temperature-7d.png" temperature-7d.png
fi
if [ "$(($counter % 21600))" = "0" ]; then  # 6 hours
    echo_err "[INFO] Recreating 1y plot..."
    plot_data "$(date -d "$(date) - 1 year" '+%Y-%m-%d %H:%M:%S %Z')" 100 10 '%m/%d' > "$output_path/temperature-1y.png"
    echo_err "[INFO] Uploading 1y plot to B2 bucket '$b2_bucket'..."
    ~/.local/bin/b2 upload-file "$b2_bucket" "$output_path/temperature-1y.png" temperature-1y.png
    echo_err "[INFO] Uploading database to B2 bucket '$b2_bucket'..."
    ~/.local/bin/b2 upload-file "$b2_bucket" "$temperature_db" temperature-readings.db
fi


# regenerate template
sed "s/%timestamp%/$timestamp/" "$html_template" | \
sed "s/%sensor1_name%/$sensor1_name/" | \
sed "s/%sensor1_temp%/$sensor1_tempf/" | \
sed "s/%sensor2_name%/$sensor2_name/" | \
sed "s/%sensor2_temp%/$sensor2_tempf/" > "$output_path/index.html"

if [ "$(($counter % 900))" = "0" ]; then  # 15 minutes
    echo_err "[INFO] Uploading 24h plot and HTML page to B2 bucket '$b2_bucket'..."
    ~/.local/bin/b2 upload-file "$b2_bucket" "$output_path/index.html" temperature.html
    ~/.local/bin/b2 upload-file "$b2_bucket" "$output_path/temperature-24h.png" temperature-24h.png
fi
