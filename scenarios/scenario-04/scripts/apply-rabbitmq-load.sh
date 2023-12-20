GIT_TLD=`git rev-parse --show-toplevel`
LOAD_NS=pending-orders
RMQ_CLUSTER_NS=prod-robot-shop
SCENARIO_TIMEOUT=5m
WAIT_TIMEOUT=5m
AWS_REGION=us-west-2
MAX_NODE=8

echo "\n Scale up loadgen-ng nodegroup... \n "
eksctl scale nodegroup --cluster=prod-eks-cluster --nodes=${MAX_NODE} --name=loadgen-ng --nodes-max=${MAX_NODE} --wait --region ${AWS_REGION}

echo "\n Creating $LOAD_NS namespace... \n"
kubectl create namespace $LOAD_NS --dry-run=client -o yaml | kubectl apply -f -

echo "\n Reducing RabbitMQ cluster resources... \n"

kubectl patch rabbitmqcluster rabbitmq-cluster --type='json' \
    -p='[
        {"op": "replace", "path": "/spec/resources/limits/cpu", "value": "200m"}, 
        {"op": "replace", "path": "/spec/resources/limits/memory", "value": "200Mi"}, 
        {"op": "replace", "path": "/spec/resources/requests/cpu", "value": "100m"}, 
        {"op": "replace", "path": "/spec/resources/requests/memory", "value": "50Mi"}, 

        ]' \
     -n $RMQ_CLUSTER_NS

echo "\n Wait for RabbitMQ cluster with resources patch \n"
sleep $WAIT_TIMEOUT

# kubectl wait --for=condition=AllReplicasReady rabbitmqcluster/rabbitmq-cluster --timeout=1m -n $RMQ_CLUSTER_NS

echo "\n Applying RabbitMQ Load.... \n"
kubectl apply -f ${GIT_TLD}/scenarios/scenario-04/rabbitmq-load.yaml -n $LOAD_NS

sleep $SCENARIO_TIMEOUT

echo "\n Removing RabbitMQ Load.... \n"
kubectl delete -f ${GIT_TLD}/scenarios/scenario-04/rabbitmq-load.yaml -n $LOAD_NS

echo "\n Scale down loadgen-ng nodegroup... \n "
eksctl scale nodegroup --cluster=prod-eks-cluster --nodes=1 --name=loadgen-ng --nodes-max=1 --wait --region ${AWS_REGION}

echo "\n Undo RabbitMQ cluster resources.... \n"
kubectl patch rabbitmqcluster rabbitmq-cluster --type='json' \
    -p='[
        {"op": "replace", "path": "/spec/resources/limits/cpu", "value": 1}, 
        {"op": "replace", "path": "/spec/resources/limits/memory", "value": "2Gi"}, 
        {"op": "replace", "path": "/spec/resources/requests/cpu", "value": "500m"}, 
        {"op": "replace", "path": "/spec/resources/requests/memory", "value": "2Gi"}, 

        ]' \
     -n $RMQ_CLUSTER_NS

# echo "\n Wait for RabbitMQ cluster up with original resources \n"
# sleep $WAIT_TIMEOUT
# kubectl wait --for=condition=AllReplicasReady rabbitmqcluster/rabbitmq-cluster --timeout=1m -n $RMQ_CLUSTER_NS


