#! /bin/bash

start_date=`date '+%Y-%m-%d %T'`
start=`date +%s -d "$start_date"`
echo $start

sleep 1.5
end_date=`date '+%Y-%m-%d %T'`
end=`date +%s -d "$end_date"`
echo $end

time1=$(($end-$start))
echo $time1
