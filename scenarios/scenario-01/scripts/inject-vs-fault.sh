#!/bin/bash

GIT_TLD=`git rev-parse --show-toplevel`
NS=robot-shop
SCENARIO_TIMEOUT=10m

echo "Injecting VirtualService fault..."

kubectl apply -f ./virtual-service-fault.yaml -n $NS

echo "\n Increase load..." 
kubectl set env deployment/load -n loadgen NUM_CLIENTS=5000

sleep $SCENARIO_TIMEOUT

echo "\n Reduce load.."
kubectl set env deployment/load -n loadgen NUM_CLIENTS=10

echo "\n Removing fault..."
kubectl apply -f ${GIT_TLD}/app/robot-shop/helm/templates/ratings-vs.yaml -n $NS