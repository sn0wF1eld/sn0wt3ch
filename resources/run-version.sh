#!/bin/bash

version=${version:-"latest"}
config=${config}
library=${library}
gc=${gc:-"G1"}
maxHeap=${maxHeap:-"2G"}
minHeap=${minHeap:-"2G"}
env=${env:-"default"}
name="sn0wf1eld/sn0wst0rm"

while [ $# -gt 0 ]; do

  if [[ $1 == *"--"* ]]; then
    param="${1/--/}"
    declare $param="$2"
  fi

  shift
done

mkdir lib

cp $library lib/extra-library.jar
cp $config lib/config.edn

cd lib

docker run --sysctl net.ipv4.tcp_keepalive_intvl=10 \
 --sysctl net.ipv4.tcp_keepalive_probes=20 \
 --sysctl net.ipv4.tcp_keepalive_time=180 \
 --network=sn0wf1eld-net \
 -p 9000:8181 \
 -e CDG_ENV=$env \
 --ip 172.20.0.10 \
 -v $PWD:/app/temp \
 -it -d $name":"$version \
 $gc $maxHeap $minHeap

rm -rf lib
