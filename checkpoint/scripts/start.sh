#!/bin/bash
for i in {1..99}; do
  sleep $i &  # Avoid PID collisions during restore
done
/usr/bin/java -XX:CRaCCheckpointTo=/var/lib/pebble/default/crac-files -jar /jars/spring-petclinic.jar
