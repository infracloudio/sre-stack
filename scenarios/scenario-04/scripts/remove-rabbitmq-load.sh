#!/bin/bash

GIT_TLD=`git rev-parse --show-toplevel`
source ${GIT_TLD}/scenarios/scenario-04/scripts/common.sh

echo "\n Removing RabbitMQ Load.... \n"
kubectl delete -f ${GIT_TLD}/scenarios/scenario-04/rabbitmq-load.yaml -n $LOAD_NS

echo "\n Scale down ${NODE_GROUP} nodegroup... \n "
eksctl scale nodegroup --cluster=${CLUSTER_NAME} --nodes=1 --name=${NODE_GROUP} --nodes-max=1 --wait --region ${AWS_REGION}

echo "\n Undo RabbitMQ cluster resources.... \n"
kubectl patch rabbitmqcluster rabbitmq-cluster --type='json' \
    -p='[
        {"op": "replace", "path": "/spec/replicas", "value": 3},
        {"op": "replace", "path": "/spec/resources/limits/cpu", "value": 1}, 
        {"op": "replace", "path": "/spec/resources/limits/memory", "value": "2Gi"}, 
        {"op": "replace", "path": "/spec/resources/requests/cpu", "value": "500m"}, 
        {"op": "replace", "path": "/spec/resources/requests/memory", "value": "2Gi"}, 
        ]' \
     -n $RMQ_CLUSTER_NS