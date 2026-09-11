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
        _cleanup_mc_group="MC_${_cleanup_rg}_${_cleanup_cluster}_${AZURE_LOCATION}"
        if [ -z "${_cleanup_rg}" ] || [ -z "${_cleanup_cluster}" ]; then
            echo "Cannot start: the generated resource group or cluster name is empty." >&2
            echo "Check the Azure settings in .env, then try again. Nothing was deleted." >&2
            exit 1
        fi

        # Read a group's existence without ever confusing "confirmed absent"
        # with "could not read" (T051): az group exists must answer exactly
        # true or false; any other exit code or output means the read failed,
        # so cleanup stops non-zero and deletes nothing.
        _az_group_state() {  # $1 group name; prints true|false; 0 = confirmed read
            _grp_out=$(az group exists --name "$1" --output tsv 2>/dev/null)
            _grp_rc=$?
            if [ "${_grp_rc}" -ne 0 ] \
                || { [ "${_grp_out}" != "true" ] && [ "${_grp_out}" != "false" ]; }; then
                echo "Cannot start: could not check whether resource group $1 exists (the Azure read failed)." >&2
                echo "Check the sign-in and the network, then run 'make cleanup-cluster' again. Nothing was deleted." >&2
                return 1
            fi
            printf '%s\n' "${_grp_out}"
            return 0
        }

        if ! _cleanup_rg_state=$(_az_group_state "${_cleanup_rg}"); then
            exit 1
        fi

        _cleanup_deleted_main=0
        if [ "${_cleanup_rg_state}" = "true" ]; then
            # Only the generated name is ever passed to delete (data-model §2,
            # contract §1 deleting); any other group is never touched.
            echo "deleting resource group ${_cleanup_rg} — this removes the cluster and its node resource group, and can take a few minutes..."
            if ! az group delete --name "${_cleanup_rg}" --yes; then
                # A failed delete must say what is known to remain, or that
                # the state could not be checked (T056/T059) — never claim
                # success, and never claim "nothing else was removed": a
                # failed delete may have removed inner resources.
                echo "Failed to delete resource group ${_cleanup_rg}." >&2
                _cleanup_after=$(az group exists --name "${_cleanup_rg}" --output tsv 2>/dev/null)
                _cleanup_after_rc=$?
                if [ "${_cleanup_after_rc}" -ne 0 ] \
                    || { [ "${_cleanup_after}" != "true" ] && [ "${_cleanup_after}" != "false" ]; }; then
                    echo "Could not confirm whether the resource group still exists (the follow-up read failed)." >&2
                elif [ "${_cleanup_after}" = "true" ]; then
                    echo "The resource group still exists; some resources may remain." >&2
                else
                    echo "The resource group is gone despite the delete command's error." >&2
                fi
                echo "Not checked: node resource group ${_cleanup_mc_group} (only checked once the main group is gone)." >&2
                echo "Check the sign-in, then run 'make cleanup-cluster' again. Some resources may remain." >&2
                exit 1
            fi
            _cleanup_deleted_main=1
        fi

        # The node resource group's name is fully predictable (contract §1
        # deleting): check that one exact name only, never a broad MC_* search.
        # The check runs even when the main group was already absent (T051) —
        # an earlier delete may have removed the group while an orphaned node
        # group remains.
        # T059: a failed MC read after a successful main delete must not say
        # "Nothing was deleted" — the main group is already gone.
        _cleanup_mc_out=$(az group exists --name "${_cleanup_mc_group}" --output tsv 2>/dev/null)
        _cleanup_mc_rc=$?
        if [ "${_cleanup_mc_rc}" -ne 0 ] \
            || { [ "${_cleanup_mc_out}" != "true" ] && [ "${_cleanup_mc_out}" != "false" ]; }; then
            if [ "${_cleanup_deleted_main}" = "1" ]; then
                echo "Cannot start: deleted resource group ${_cleanup_rg}, but could not check whether node resource group ${_cleanup_mc_group} still exists (the Azure read failed)." >&2
                echo "Check the sign-in and the network, then run 'make cleanup-cluster' again. The main group was deleted; some resources may remain." >&2
            elif [ "${_cleanup_rg_state}" = "true" ]; then
                echo "Cannot start: could not check whether resource group ${_cleanup_mc_group} exists (the Azure read failed)." >&2
                echo "Check the sign-in and the network, then run 'make cleanup-cluster' again. Nothing was confirmed deleted." >&2
            else
                echo "Cannot start: could not check whether resource group ${_cleanup_mc_group} exists (the Azure read failed)." >&2
                echo "Check the sign-in and the network, then run 'make cleanup-cluster' again. The main group is already absent; the node group state is unknown and some resources may remain." >&2
            fi
            exit 1
        fi
        _cleanup_mc_state="${_cleanup_mc_out}"
        if [ "${_cleanup_mc_state}" = "true" ]; then
            echo "Resource group ${_cleanup_rg} is gone, but its node resource group still exists: ${_cleanup_mc_group}" >&2
            echo "Remove it with: az group delete --name ${_cleanup_mc_group} --yes" >&2
            exit 1
        fi

        if [ "${_cleanup_rg_state}" != "true" ]; then
            echo "Nothing to clean: resource group ${_cleanup_rg} does not exist."
            exit 0
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
