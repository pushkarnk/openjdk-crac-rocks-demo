#!/bin/bash
for i in {1..9999}; do
  sleep $i &
done
/usr/bin/java -XX:CRaCCheckpointTo=/var/lib/pebble/default/crac-files -jar /jars/spring-petclinic.jar
