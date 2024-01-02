#!/bin/bash

GIT_TLD=`git rev-parse --show-toplevel`
source ${GIT_TLD}/scenarios/scenario-04/scripts/common.sh

echo "\n Removing RabbitMQ Load.... \n"
kubectl delete -f ${GIT_TLD}/scenarios/scenario-04/rabbitmq-load.yaml -n ${SCENARIO_04_LOAD_NS}

echo "\n Scale down ${LOADGEN_NODE_GROUP_NAME} nodegroup... \n "
eksctl scale nodegroup --cluster=${CLUSTER_NAME} --nodes=1 --name=${LOADGEN_NODE_GROUP_NAME} --nodes-max=1 --wait --region ${AWS_REGION}

echo "\n Undo RabbitMQ cluster resources.... \n"
kubectl patch rabbitmqcluster ${RMQ_CLUSTER_NAME} --type='json' \
    -p='[
        {"op": "replace", "path": "/spec/replicas", "value": 3},
        {"op": "replace", "path": "/spec/resources/limits/cpu", "value": 1}, 
        {"op": "replace", "path": "/spec/resources/limits/memory", "value": "2Gi"}, 
        {"op": "replace", "path": "/spec/resources/requests/cpu", "value": "500m"}, 
        {"op": "replace", "path": "/spec/resources/requests/memory", "value": "2Gi"}, 
        ]' \
     -n $RMQ_CLUSTER_NS