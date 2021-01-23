#!/bin/sh
#
# The actual values for following variables should be set by the env file
# sensor1_uuid="28-011937c85701"
# sensor1_name="air"
# sensor2_uuid="28-01193804ca0b"
# sensor2_name="water"
# temperature_db="temperature-readings.db"
# output_path="."
set -eu

source ./env

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

plot_data "$(date -d "$(date) - 24 hours" '+%Y-%m-%d %H:%M:%S %Z')" 10 2 '%m/%d %H:%M' > "$output_path/temperature-24h.png"
plot_data "$(date -d "$(date) - 7 days" '+%Y-%m-%d %H:%M:%S %Z')" 20 5 '%m/%d' > "$output_path/temperature-7d.png"
plot_data "$(date -d "$(date) - 1 year" '+%Y-%m-%d %H:%M:%S %Z')" 100 10 '%m/%d' > "$output_path/temperature-1y.png"
