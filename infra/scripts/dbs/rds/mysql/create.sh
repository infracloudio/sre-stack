#!/bin/bash

GIT_TLD=`git rev-parse --show-toplevel`
source ${GIT_TLD}/scripts/dbs/rds/common.sh

echo "\nAdd security mmysql security group rules"
aws ec2 authorize-security-group-ingress \
  --group-id ${RDS_VPC_SECURITY_GROUP_ID}\
  --protocol tcp \
  --port 3306 \
  --source-group ${CLUSTER_SG} \
  --region us-east-1

## Create subnet group
echo "\nCreate DB subnet group..."
aws rds create-db-subnet-group --db-subnet-group-name robotshop-mysql-subnet-group --db-subnet-group-description "robotsho pmysql subnet group" --subnet-ids $SUBNET --region us-east-1
# aws rds create-db-subnet-group -cli-input-json "{\"DBSubnetGroupName\":\"robotshop-mysql-subnet-group\",\"DBSubnetGroupDescription\":\"robotsho pmysql subnet group\",\"SubnetIds\":$SUBNET}" --region us-east-1

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
  --backup-retention-period 0 \
  --region us-east-1 \
  --port 3306 

echo "\n Wait for MYSQL DB..."
aws rds wait db-instance-available --db-instance-identifier robotshopmysql  --region us-east-1 

## GET DB endpoint
export MYSQL_HOST=$(aws rds describe-db-instances --db-instance-identifier robotshopmysql --region us-east-1 --query 'DBInstances[*].Endpoint.Address' --output text)
