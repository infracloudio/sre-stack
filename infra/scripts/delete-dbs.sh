#!/bin/bash

aws rds delete-db-instance --db-instance-identifier robotshopmysql --skip-final-snapshot  --region us-east-1

aws rds wait db-instance-deleted --db-instance-identifier robotshopmysql  --region us-east-1

aws rds delete-db-subnet-group --db-subnet-group-name robotshopmysql-subnet-group --region us-east-1

RDS_VPC_SECURITY_GROUP_ID=$(aws ec2 describe-security-groups --region us-east-1  --filters Name=group-name,Values=RobotShopRDSSecurityGroup --query 'SecurityGroups[*].GroupId' --output text)
aws ec2 delete-security-group --group-id $RDS_VPC_SECURITY_GROUP_ID --region us-east-1

## Clean DocumentDB...

aws docdb delete-db-instance --db-instance-identifier robotshopdocdb-instance --region us-east-1

aws docdb wait db-instance-deleted --db-instance-identifier robotshopdocdb-instance --region us-east-1

aws docdb delete-db-cluster --db-cluster-identifier robotshopdocdb-cluster --skip-final-snapshot

sleep 60

aws docdb delete-db-subnet-group --db-subnet-group-name robotshop-docdb-subnet-group --region us-east-1



