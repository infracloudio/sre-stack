#!/bin/bash

GIT_TLD=`git rev-parse --show-toplevel`
NS=robot-shop
SCENARIO_TIMEOUT=10m

echo "Injecting mis-configured health probes..."

kubectl patch deployment ratings --type='json' \
    -p='[
        {"op": "replace", "path": "/spec/template/spec/containers/0/readinessProbe/initialDelaySeconds", "value": 120}, 
        {"op": "replace", "path": "/spec/template/spec/containers/0/readinessProbe/periodSeconds", "value": 120}
        ]' \
     -n $NS

echo "\n Increase load..." 
kubectl set env deployment/load -n loadgen NUM_CLIENTS=5000

sleep $SCENARIO_TIMEOUT

echo "\n Reduce load..."
kubectl set env deployment/load -n loadgen NUM_CLIENTS=10

echo "\n Removing mis-configured health probes..."
kubectl patch deployment ratings --type='json' \
    -p='[
        {"op": "replace", "path": "/spec/template/spec/containers/0/readinessProbe/initialDelaySeconds", "value": 5}, 
        {"op": "replace", "path": "/spec/template/spec/containers/0/readinessProbe/periodSeconds", "value": 5}
        ]' \
     -n $NS