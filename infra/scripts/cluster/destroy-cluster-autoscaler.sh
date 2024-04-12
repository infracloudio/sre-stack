#!/bin/bash
GIT_TLD=`git rev-parse --show-toplevel`
source ${GIT_TLD}/.env

CHECK_ASG_POLICY_EXISTS=$(aws iam list-policies --query "Policies[?PolicyName=='${AUTO_SCALING_GROUP_POLICY_NAME}'].Arn" --output text --no-cli-pager)
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text --no-cli-pager)

if [ -n "${CHECK_ASG_POLICY_EXISTS}" ]; then
    eksctl delete iamserviceaccount \
	--region=${AWS_REGION} --name cluster-autoscaler \
	--namespace kube-system \
	--cluster ${CLUSTER_NAME} 
	aws iam delete-policy --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${AUTO_SCALING_GROUP_POLICY_NAME}
else
    echo "${AUTO_SCALING_GROUP_POLICY_NAME} policy does not exists."
fi