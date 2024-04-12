#!/bin/bash
GIT_TLD=`git rev-parse --show-toplevel`
source ${GIT_TLD}/.env

CHECK_CLUSTER_EXISTS=$(aws eks describe-cluster --name ${CLUSTER_NAME} --query 'cluster.arn' --output text --region ${AWS_REGION} --no-cli-pager 2>/dev/null)
if [ -z "${CHECK_CLUSTER_EXISTS}" ]; then
    echo "Creating ${CLUSTER_NAME} cluster..."
    eksctl create cluster -f infra/eksctl.yaml
else 
    echo "${CLUSTER_NAME} cluster already exists."
fi

