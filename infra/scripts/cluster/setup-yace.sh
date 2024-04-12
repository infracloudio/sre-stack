#!/bin/bash
GIT_TLD=`git rev-parse --show-toplevel`
source ${GIT_TLD}/.env

CHECK_YACE_POLICY_EXISTS=$(aws iam list-policies --query "Policies[?PolicyName=='${YACE_CLOUDWATCH_POLICY_NAME}'].Arn" --output text --no-cli-pager)
OBSERVABILITY_NODEGROUP_ROLE_NAME=$(eksctl get nodegroup --cluster "${CLUSTER_NAME}" --region "${AWS_REGION}" --output json | jq -r ".[] | select(.Name == \"${OBSERVABILITY_NODEGROUP_NAME}\") | .NodeInstanceRoleARN | split(\"/\") | .[1]")

if [ -z "${CHECK_YACE_POLICY_EXISTS}" ]; then
    POLICY_ARN=$(aws iam create-policy  \
	--policy-name ${YACE_CLOUDWATCH_POLICY_NAME} \
	--policy-document file://${GIT_TLD}/infra/yace-cloudwatch-policy.json \
    --query 'Policy.Arn' \
    --output text \
    --no-cli-pager 2>/dev/null)
else
	echo "Yace policy already exists ${CHECK_YACE_POLICY_EXISTS}"
    POLICY_ARN=${CHECK_YACE_POLICY_EXISTS}
fi

if [ -n "${POLICY_ARN}" ] && [ -n "${OBSERVABILITY_NODEGROUP_ROLE_NAME}" ]; then 
	aws iam attach-role-policy --role-name ${OBSERVABILITY_NODEGROUP_ROLE_NAME} --policy-arn ${POLICY_ARN}
	helm repo add yace https://nerdswords.github.io/helm-charts
	helm upgrade --install yace yace/yet-another-cloudwatch-exporter -f monitoring/chart-values/yace.yaml --set aws_region=${AWS_REGION} --set db_name=${RDS_MYSQL_DB_NAME} --create-namespace -n ${MONITORING_NS}
else 
    echo "Faild to create and attach ${YACE_CLOUDWATCH_POLICY_NAME} policy."
    exit 1 
fi