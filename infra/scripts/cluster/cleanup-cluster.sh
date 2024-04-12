#!/bin/bash
GIT_TLD=`git rev-parse --show-toplevel`
source ${GIT_TLD}/.env

CHECK_CLUSTER_EXISTS=$(aws eks describe-cluster --name ${CLUSTER_NAME} --query 'cluster.arn' --output text --region ${AWS_REGION} --no-cli-pager 2>/dev/null)
if [ -n "${CHECK_CLUSTER_EXISTS}" ]; then
    eksctl delete cluster --region=${AWS_REGION} --name=${CLUSTER_NAME} --wait
else 
    echo "${CLUSTER_NAME} cluster does not exists."
fi



