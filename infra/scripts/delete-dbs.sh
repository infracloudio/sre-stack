#!/bin/bash

AWS_REGION=us-east-1

aws rds delete-db-instance --db-instance-identifier robotshopmysql --skip-final-snapshot  --region ${AWS_REGION} --no-cli-pager

aws rds wait db-instance-deleted --db-instance-identifier robotshopmysql  --region ${AWS_REGION} --no-cli-pager

aws rds delete-db-subnet-group --db-subnet-group-name robotshopmysql-subnet-group --region ${AWS_REGION} --no-cli-pager

RDS_VPC_SECURITY_GROUP_ID=$(aws ec2 describe-security-groups --region ${AWS_REGION}  --filters Name=group-name,Values=RobotShopRDSSecurityGroup --query 'SecurityGroups[*].GroupId' --output text --no-cli-pager) 
aws ec2 delete-security-group --group-id $RDS_VPC_SECURITY_GROUP_ID --region ${AWS_REGION} --no-cli-pager

## Clean DocumentDB...

aws docdb delete-db-instance --db-instance-identifier robotshopdocdb-instance --region ${AWS_REGION} --no-cli-pager

aws docdb wait db-instance-deleted --db-instance-identifier robotshopdocdb-instance --region ${AWS_REGION} --no-cli-pager

aws docdb delete-db-cluster --db-cluster-identifier robotshopdocdb-cluster --skip-final-snapshot --region ${AWS_REGION} --no-cli-pager

sleep 60

aws docdb delete-db-subnet-group --db-subnet-group-name robotshop-docdb-subnet-group --region ${AWS_REGION} --no-cli-pager



