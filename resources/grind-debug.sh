#!/bin/bash

version=${version:-"latest"}
config=${config}
baseLibrary=${baseLibrary}
library=${library}
gc=${gc:-"G1"}
maxHeap=${maxHeap:-"4G"}
minHeap=${minHeap:-"2G"}

while [ $# -gt 0 ]; do

  if [[ $1 == *"--"* ]]; then
    param="${1/--/}"
    declare $param="$2"
  fi

  shift
done

BASEDIR=$(pwd)

./header.sh

cp  $baseLibrary $BASEDIR/sn0wst0rm-standalone.jar

if [ ! -z "PIPELINE_CONF" ]
then
  cp $config $BASEDIR
fi

if [ ! -z "$library" ]
then
  cp  $library $BASEDIR/extra-library.jar
  java --enable-preview "-XX:+Use"$gc"GC" "-Xmx$maxHeap" "-Xms$minHeap" -agentlib:jdwp=transport=dt_socket,server=y,suspend=y,address=6969 -cp sn0wst0rm-standalone.jar:extra-library.jar sn0wst0rm.core
else
  java --enable-preview "-XX:+Use"$gc"GC" "-Xmx$maxHeap" "-Xms$minHeap" -agentlib:jdwp=transport=dt_socket,server=y,suspend=y,address=6969 -cp sn0wst0rm-standalone.jar sn0wst0rm.core
fi
