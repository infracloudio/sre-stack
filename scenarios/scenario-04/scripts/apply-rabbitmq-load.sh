#!/bin/bash 

GIT_TLD=`git rev-parse --show-toplevel`
source ${GIT_TLD}/scenarios/scenario-04/scripts/common.sh

echo "\n Creating ${SCENARIO_04_LOAD_NS} namespace... \n"
kubectl create namespace ${SCENARIO_04_LOAD_NS} --dry-run=client -o yaml | kubectl apply -f -

echo "\n Reducing RabbitMQ cluster resources... \n"

kubectl patch rabbitmqcluster ${RMQ_CLUSTER_NAME} --type='json' \
    -p='[
        {"op": "replace", "path": "/spec/resources/limits/cpu", "value": "200m"}, 
        {"op": "replace", "path": "/spec/resources/limits/memory", "value": "200Mi"}, 
        {"op": "replace", "path": "/spec/resources/requests/cpu", "value": "100m"}, 
        {"op": "replace", "path": "/spec/resources/requests/memory", "value": "50Mi"}, 

        ]' \
     -n ${RMQ_CLUSTER_NS}

echo "\n Wait for RabbitMQ cluster with resources patch \n"
sleep ${SCENARIO_04_WAIT_TIMEOUT}

echo "\n Scale up ${LOADGEN_NODE_GROUP_NAME} nodegroup... \n "
eksctl scale nodegroup --cluster=${CLUSTER_NAME} --nodes=${LOADGEN_NODE_MAX_NODE} --name=${LOADGEN_NODE_GROUP_NAME} --nodes-max=${LOADGEN_NODE_MAX_NODE} --wait --region ${AWS_REGION}

echo "\n Applying RabbitMQ Load.... \n"
kubectl apply -f ${GIT_TLD}/scenarios/scenario-04/rabbitmq-load.yaml -n ${SCENARIO_04_LOAD_NS}

