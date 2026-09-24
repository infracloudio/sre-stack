#!/bin/bash
GIT_TLD=`git rev-parse --show-toplevel`
source ${GIT_TLD}/.env
cd "${GIT_TLD}" || exit 1

case "${STACK_MODE:-}" in
    aks)
        exec "${GIT_TLD}/infra/scripts/cluster/setup-cluster-aks.sh"
        ;;
    eks|local)
        ;;
    *)
        echo "Cannot start: STACK_MODE is '${STACK_MODE:-}' but must be eks | local | aks." >&2
        echo "Set it in .env, then try again. Nothing was created." >&2
        exit 1
        ;;
esac

CHECK_CLUSTER_EXISTS=$(aws eks describe-cluster --name ${CLUSTER_NAME} --query 'cluster.arn' --output text --region ${AWS_REGION} --no-cli-pager 2>/dev/null)
if [ -z "${CHECK_CLUSTER_EXISTS}" ]; then
    echo "Creating ${CLUSTER_NAME} cluster..."
    eksctl create cluster -f infra/eksctl.yaml
else 
    echo "${CLUSTER_NAME} cluster already exists."
fi
