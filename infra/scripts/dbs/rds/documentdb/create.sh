#!/bin/bash

GIT_TLD=`git rev-parse --show-toplevel`
source ${GIT_TLD}/infra/scripts/dbs/rds/common.sh

echo "\nAdd security mmysql doucumentdb security group rules"
aws ec2 authorize-security-group-ingress \
  --group-id ${RDS_VPC_SECURITY_GROUP_ID}\
  --protocol tcp \
  --port 27017 \
  --source-group ${CLUSTER_SG} \
  --region ${AWS_REGION}

## create subnet group
echo "\nCreate DocumentDB subnet group..."
aws docdb create-db-subnet-group --cli-input-json "{\"DBSubnetGroupName\":\"${DOC_DB_SUBNET_GROUP_NAME}\",\"DBSubnetGroupDescription\":\"robotshop docdb subnet group\",\"SubnetIds\":$SUBNET}" --region ${AWS_REGION}

## documentDB Parameter Group
# crate if not exists
# This should be one time because we don't need to clean up it every-time
# # Create
# aws docdb create-db-cluster-parameter-group \
#  --db-cluster-parameter-group-name tls-disabled-docdb50-parameter-group \
#  --db-parameter-group-family docdb5.0 \
#  --description "Custom docdb5.0 parameter group where TLS is disabled"

# # Modify
# modifiy if not modified
# aws docdb modify-db-cluster-parameter-group \
#     --db-cluster-parameter-group-name tls-disabled-docdb50-parameter-group \
#     --parameters "ParameterName=tls,ParameterValue=disabled,ApplyMethod=pending-reboot"

echo "\nCreate DocumentDB..."
## Create Cluster
aws docdb create-db-cluster \
  --db-cluster-identifier ${DOC_DB_CLUSTER_NAME} \
  --vpc-security-group-ids ${RDS_VPC_SECURITY_GROUP_ID} \
  --db-subnet-group-name ${DOC_DB_SUBNET_GROUP_NAME} \
  --db-cluster-parameter-group-name ${DOC_DB_PARAMETER_GROUP_NAME} \
  --engine docdb \
  --engine-version ${DOC_DB_ENGINE_VERSION} \
  --deletion-protection \
  --master-username ${DOC_DB_MASTER_USERNAME} \
  --master-user-password ${DOC_DB_MASTER_PASSWORD} \
  --no-deletion-protection \
  --region ${AWS_REGION}

sleep 60

echo "\nAdd DocumentDB Instance in DocumentDB..."
aws docdb create-db-instance \
  --db-instance-identifier ${DOC_DB_INSTANCE_NAME} \
  --db-instance-class ${DOC_DB_INSTANCE_CLASS} \
  --engine docdb \
  --db-cluster-identifier ${DOC_DB_CLUSTER_NAME} \
  --region ${AWS_REGION}

echo "\nWait for DocumentDB Instance..."
aws docdb wait db-instance-available --db-instance-identifier ${DOC_DB_INSTANCE_NAME} --region ${AWS_REGION}

export MONGODB_HOST=$(aws docdb describe-db-clusters --db-cluster-identifier ${DOC_DB_CLUSTER_NAME} --region ${AWS_REGION} --query 'DBClusters[*].Endpoint' --output text)