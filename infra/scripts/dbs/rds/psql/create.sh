#!/bin/bash

GIT_TLD=`git rev-parse --show-toplevel`
source ${GIT_TLD}/infra/scripts/dbs/rds/common.sh

echo "\nAdd security psql security group rules"
aws ec2 authorize-security-group-ingress \
  --group-id ${RDS_VPC_SECURITY_GROUP_ID}\
  --protocol tcp \
  --port 5432 \
  --source-group ${CLUSTER_SG} \
  --region ${AWS_REGION} \
  --no-cli-pager

## Create subnet group
echo "\nCreate PSQL DB subnet group..."
aws rds create-db-subnet-group --cli-input-json "{\"DBSubnetGroupName\":\"grafana-psql-subnet-group\",\"DBSubnetGroupDescription\":\"grafana psql subnet group\",\"SubnetIds\":$SUBNET}" --region ${AWS_REGION} --no-cli-pager

######## Create psql db 
echo "\nCreate PSQL DB..."
aws rds create-db-instance \
  --db-name grafanapsql \
  --db-instance-identifier grafanapsql \
  --allocated-storage 10 \
  --db-instance-class db.t3.micro \
  --engine postgres \
  --engine-version "16.1" \
  --master-username grafana \
  --master-user-password postgres \
  --no-publicly-accessible \
  --vpc-security-group-ids ${RDS_VPC_SECURITY_GROUP_ID} \
  --db-subnet-group-name "grafana-psql-subnet-group" \
  --backup-retention-period 0 \
  --region ${AWS_REGION} \
  --tags Key=name,Value=grafanapsql \
  --port 5432 \
  --no-cli-pager

echo "\n Wait for PSQL DB..."
aws rds wait db-instance-available --db-instance-identifier grafanapsql  --region ${AWS_REGION} 

## GET DB endpoint
export PSQL_HOST=$(aws rds describe-db-instances --db-instance-identifier grafanapsql --region ${AWS_REGION} --query 'DBInstances[*].Endpoint.Address' --output text)
