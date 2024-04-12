#!/bin/bash
GIT_TLD=`git rev-parse --show-toplevel`
source ${GIT_TLD}/.env

CHECK_YACE_POLICY_EXISTS=$(aws iam list-policies --query "Policies[?PolicyName=='${YACE_CLOUDWATCH_POLICY_NAME}'].Arn" --output text --no-cli-pager)
OBSERVABILITY_NODEGROUP_ROLE_NAME=$(eksctl get nodegroup --cluster "${CLUSTER_NAME}" --region "${AWS_REGION}" --output json | jq -r ".[] | select(.Name == \"${OBSERVABILITY_NODEGROUP_NAME}\") | .NodeInstanceRoleARN | split(\"/\") | .[1]")
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text --no-cli-pager)

if [ -n "${CHECK_YACE_POLICY_EXISTS}" ]; then
    aws iam detach-role-policy --role-name ${OBSERVABILITY_NODEGROUP_ROLE_NAME} --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${YACE_CLOUDWATCH_POLICY_NAME}
	aws iam delete-policy --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${YACE_CLOUDWATCH_POLICY_NAME}
else
    echo "${YACE_CLOUDWATCH_POLICY_NAME} policy does not exists."
fi