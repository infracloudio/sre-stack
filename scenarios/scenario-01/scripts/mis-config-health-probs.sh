#!/bin/bash

GIT_TLD=`git rev-parse --show-toplevel`
source ${GIT_TLD}/.env
echo "Injecting mis-configured health probes..."

kubectl patch deployment ratings --type='json' \
    -p='[
        {"op": "replace", "path": "/spec/template/spec/containers/0/readinessProbe/initialDelaySeconds", "value": 120}, 
        {"op": "replace", "path": "/spec/template/spec/containers/0/readinessProbe/periodSeconds", "value": 120}
        ]' \
     -n ${APP_NS}

echo "\n Increase load..." 
kubectl set env deployment/load -n loadgen NUM_CLIENTS=${LOADGEN_MAX_NUM_CLIENTS}

sleep ${SCENARIO_01_TIMEOUT}

echo "\n Reduce load..."
kubectl set env deployment/load -n loadgen NUM_CLIENTS=${LOADGEN_MIN_NUM_CLIENTS}

echo "\n Removing mis-configured health probes..."
kubectl patch deployment ratings --type='json' \
    -p='[
        {"op": "replace", "path": "/spec/template/spec/containers/0/readinessProbe/initialDelaySeconds", "value": 5}, 
        {"op": "replace", "path": "/spec/template/spec/containers/0/readinessProbe/periodSeconds", "value": 5}
        ]' \
     -n ${APP_NS}