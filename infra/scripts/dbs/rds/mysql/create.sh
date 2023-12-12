#!/bin/bash

GIT_TLD=`git rev-parse --show-toplevel`
source ${GIT_TLD}/infra/scripts/dbs/rds/common.sh

echo "\nAdd security mmysql security group rules"
aws ec2 authorize-security-group-ingress \
  --group-id ${RDS_VPC_SECURITY_GROUP_ID}\
  --protocol tcp \
  --port 3306 \
  --source-group ${CLUSTER_SG} \
  --region ${AWS_REGION} \
  --no-cli-pager

## Create subnet group
echo "\nCreate DB subnet group..."
# aws rds create-db-subnet-group --db-subnet-group-name robotshop-mysql-subnet-group --db-subnet-group-description "robotsho pmysql subnet group" --subnet-ids $SUBNET --region ${AWS_REGION}
aws rds create-db-subnet-group --cli-input-json "{\"DBSubnetGroupName\":\"robotshop-mysql-subnet-group\",\"DBSubnetGroupDescription\":\"robotshop mysql subnet group\",\"SubnetIds\":$SUBNET}" --region ${AWS_REGION} --no-cli-pager

######## Create mysql db 
echo "\nCreate MYSQL DB..."
aws rds create-db-instance \
  --db-name robotshopmysql \
  --db-instance-identifier robotshopmysql \
  --allocated-storage 10 \
  --db-instance-class db.t2.micro \
  --engine mysql \
  --engine-version "5.7.37" \
  --master-username admin \
  --master-user-password docdb3421z \
  --no-publicly-accessible \
  --vpc-security-group-ids ${RDS_VPC_SECURITY_GROUP_ID} \
  --db-subnet-group-name "robotshop-mysql-subnet-group" \
  --db-parameter-group-name sre-stack-mysql57 \
  --backup-retention-period 0 \
  --region ${AWS_REGION} \
  --tags Key=name,Value=robotshopmysql \
  --port 3306 \
  --no-cli-pager

echo "\n Wait for MYSQL DB..."
aws rds wait db-instance-available --db-instance-identifier robotshopmysql  --region ${AWS_REGION} 

## GET DB endpoint
export MYSQL_HOST=$(aws rds describe-db-instances --db-instance-identifier robotshopmysql --region ${AWS_REGION} --query 'DBInstances[*].Endpoint.Address' --output text)
