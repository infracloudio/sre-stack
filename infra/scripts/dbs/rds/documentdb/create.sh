#!/bin/bash

GIT_TLD=`git rev-parse --show-toplevel`
source ${GIT_TLD}/scripts/dbs/rds/common.sh

source ../common.sh

echo "\nAdd security mmysql doucumentdb security group rules"
aws ec2 authorize-security-group-ingress \
  --group-id ${RDS_VPC_SECURITY_GROUP_ID}\
  --protocol tcp \
  --port 27017 \
  --source-group ${CLUSTER_SG} \
  --region us-east-1

## create subnet group
echo "\nCreate DocumentDB subnet group..."
aws docdb create-db-subnet-group --cli-input-json "{\"DBSubnetGroupName\":\"robotshop-docdb-subnet-group\",\"DBSubnetGroupDescription\":\"robotshop docdb subnet group\",\"SubnetIds\":$SUBNET}" --region us-east-1

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
  --db-cluster-identifier robotshopdocdb-cluster \
  --vpc-security-group-ids ${RDS_VPC_SECURITY_GROUP_ID} \
  --db-subnet-group-name robotshop-docdb-subnet-group \
  --db-cluster-parameter-group-name tls-disabled-docdb50-parameter-group \
  --engine docdb \
  --engine-version "5.0.0" \
  --deletion-protection \
  --master-username roboadmin \
  --master-user-password docdb3421z \
  --no-deletion-protection \
  --region us-east-1

sleep 60

echo "\nAdd DocumentDB Instance in DocumentDB..."
aws docdb create-db-instance \
  --db-instance-identifier robotshopdocdb-instance \
  --db-instance-class db.t3.medium \
  --engine docdb \
  --db-cluster-identifier robotshopdocdb-cluster \
  --region us-east-1

echo "\nWait for DocumentDB Instance..."
aws docdb wait db-instance-available --db-instance-identifier robotshopdocdb-instance --region us-east-1

export MONGODB_HOST=$(aws docdb describe-db-clusters --db-cluster-identifier robotshopdocdb-cluster --region us-east-1 --query 'DBClusters[*].Endpoint' --output text)