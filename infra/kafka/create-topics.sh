#!/bin/bash

KAFKA=kafka:9092

topics=(
  mdm.entity.created
  mdm.entity.updated
  mdm.entity.matched
  mdm.entity.merged
  mdm.golden.created
  mdm.golden.updated
  mdm.survivorship.completed
  mdm.workflow.started
  mdm.workflow.completed
  mdm.audit.events
)

for topic in "${topics[@]}"
do
  kafka-topics \
    --bootstrap-server $KAFKA \
    --create \
    --if-not-exists \
    --topic $topic \
    --replication-factor 1 \
    --partitions 3
done