#!/bin/bash
GIT_TLD=`git rev-parse --show-toplevel`
source ${GIT_TLD}/.env

case "${STACK_MODE:-}" in
    aks)
        AZURE_CLEANUP=1
        export AZURE_CLEANUP
        # shellcheck disable=SC1091
        source "${GIT_TLD}/infra/scripts/cluster/azure-common.sh" || exit 1

        _cleanup_rg="${AZURE_RESOURCE_GROUP}"
        _cleanup_cluster="${AZURE_CLUSTER_NAME}"
        if [ -z "${_cleanup_rg}" ] || [ -z "${_cleanup_cluster}" ]; then
            echo "Cannot start: the generated resource group or cluster name is empty." >&2
            echo "Check the Azure settings in .env, then try again. Nothing was deleted." >&2
            exit 1
        fi

        if [ "$(az group exists --name "${_cleanup_rg}" --output tsv 2>/dev/null)" != "true" ]; then
            echo "Nothing to clean: resource group ${_cleanup_rg} does not exist."
            exit 0
        fi

        # Only the generated name is ever passed to delete (data-model §2,
        # contract §1 deleting); any other group is never touched.
        echo "deleting resource group ${_cleanup_rg} — this removes the cluster and its node resource group, and can take a few minutes..."
        if ! az group delete --name "${_cleanup_rg}" --yes; then
            echo "Failed to delete resource group ${_cleanup_rg}." >&2
            echo "Check the sign-in, then run 'make cleanup-cluster' again. Some resources may remain." >&2
            exit 1
        fi

        # The node resource group's name is fully predictable (contract §1
        # deleting): check that one exact name only, never a broad MC_* search.
        _cleanup_mc_group="MC_${_cleanup_rg}_${_cleanup_cluster}_${AZURE_LOCATION}"
        if az group show --name "${_cleanup_mc_group}" >/dev/null 2>&1; then
            echo "Resource group ${_cleanup_rg} was deleted, but its node resource group still exists: ${_cleanup_mc_group}" >&2
            echo "Remove it with: az group delete --name ${_cleanup_mc_group} --yes" >&2
            exit 1
        fi

        echo "Cleaned up: resource group ${_cleanup_rg} and its node resource group are gone."
        exit 0
        ;;
    eks|local)
        ;;
    *)
        echo "Cannot start: STACK_MODE is '${STACK_MODE:-}' but must be eks | local | aks." >&2
        echo "Set it in .env, then try again. Nothing was deleted." >&2
        exit 1
        ;;
esac

CHECK_CLUSTER_EXISTS=$(aws eks describe-cluster --name ${CLUSTER_NAME} --query 'cluster.arn' --output text --region ${AWS_REGION} --no-cli-pager 2>/dev/null)
if [ -n "${CHECK_CLUSTER_EXISTS}" ]; then
    eksctl delete cluster --region=${AWS_REGION} --name=${CLUSTER_NAME} --wait
else 
    echo "${CLUSTER_NAME} cluster does not exists."
fi
