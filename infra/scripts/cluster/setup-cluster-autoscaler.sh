#!/bin/bash
GIT_TLD=`git rev-parse --show-toplevel`
source ${GIT_TLD}/.env

CHECK_ASG_POLICY_EXISTS=$(aws iam list-policies --query "Policies[?PolicyName=='${AUTO_SCALING_GROUP_POLICY_NAME}'].Arn" --output text --no-cli-pager)

eksctl utils associate-iam-oidc-provider \
    --region=${AWS_REGION} --cluster ${CLUSTER_NAME} \
    --approve

if [ -z "${CHECK_ASG_POLICY_EXISTS}" ]; then
    POLICY_ARN=$(aws iam create-policy \
        --policy-name ${AUTO_SCALING_GROUP_POLICY_NAME} \
        --policy-document file://${GIT_TLD}/infra/asg-policy.json \
        --query 'Policy.Arn' \
        --output text \
        --no-cli-pager \
        2>/dev/null)
else
    echo "${AUTO_SCALING_GROUP_POLICY_NAME} policy already exists."
    POLICY_ARN=${CHECK_ASG_POLICY_EXISTS}
fi

if [ -n "${POLICY_ARN}" ]; then
    eksctl create iamserviceaccount \
    --region=${AWS_REGION} --name cluster-autoscaler \
    --namespace kube-system \
    --cluster ${CLUSTER_NAME} \
    --attach-policy-arn ${POLICY_ARN} \
    --approve \
    --override-existing-serviceaccounts

    kubectl apply -f infra/cluster-autoscale.yaml

    kubectl -n kube-system \
    annotate deployment.apps/cluster-autoscaler \
    cluster-autoscaler.kubernetes.io/safe-to-evict="false"
else 
    echo "Faild to create ${AUTO_SCALING_GROUP_POLICY_NAME} policy."
    exit 1 
fi