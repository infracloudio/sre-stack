#!/bin/bash

GIT_TLD=`git rev-parse --show-toplevel`
source ${GIT_TLD}/scenarios/scenario-04/scripts/common.sh

echo "\n Reduce rabbitmq load... \n"
kubectl scale --replicas=10 deployment/pending-orders-recreation -n ${SCENARIO_04_LOAD_NS}

echo "\n Scale up RabbitMQ cluster resources.... \n"
kubectl patch rabbitmqcluster ${RMQ_CLUSTER_NAME} --type='json' \
    -p='[
        {"op": "replace", "path": "/spec/replicas", "value": 6}, 
        {"op": "replace", "path": "/spec/resources/limits/memory", "value": "400Mi"}, 
        {"op": "replace", "path": "/spec/resources/requests/memory", "value": "100Mi"}, 
        ]' \
     -n $RMQ_CLUSTER_NS

sleep 600

echo "\n Scale up ${LOADGEN_NODE_GROUP_NAME} nodegroup... \n "
eksctl scale nodegroup --cluster=${CLUSTER_NAME} --nodes=${LOADGEN_NODE_MAX_NODE} --name=${LOADGEN_NODE_GROUP_NAME} --nodes-max=${LOADGEN_NODE_MAX_NODE} --wait --region ${AWS_REGION}

echo "\n Increase rabbitmq load... \n"
kubectl scale --replicas=400 deployment/pending-orders-recreation -n ${SCENARIO_04_LOAD_NS}