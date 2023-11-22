#!/bin/bash

RDS_VPC_ID=$(aws eks describe-cluster --name prod-eks-cluster --region us-east-1 --query "cluster.resourcesVpcConfig.vpcId" --output text)

# # ## Create security group
aws ec2 create-security-group --group-name RobotShopRDSSecurityGroup --vpc-id ${RDS_VPC_ID} --description "RobotShop RDS security group" --region us-east-1 

# # ## Get Security group ID; NOTE: This SG is shared b/w RDS and DocumentDB/MongoDB below
RDS_VPC_SECURITY_GROUP_ID=$(aws ec2 describe-security-groups --region us-east-1  --filters Name=group-name,Values=RobotShopRDSSecurityGroup --query 'SecurityGroups[*].GroupId' --output text)

# ## Add rule in security group

CLUSTER_SG=$(aws eks describe-cluster --name prod-eks-cluster --region us-east-1 --query "cluster.resourcesVpcConfig.clusterSecurityGroupId" --output text)

aws ec2 authorize-security-group-ingress \
  --group-id ${RDS_VPC_SECURITY_GROUP_ID}\
  --protocol tcp \
  --port 3306 \
  --source-group ${CLUSTER_SG} \
  --region us-east-1

aws ec2 authorize-security-group-ingress \
  --group-id ${RDS_VPC_SECURITY_GROUP_ID}\
  --protocol tcp \
  --port 27017 \
  --source-group ${CLUSTER_SG} \
  --region us-east-1

## Get private subnet IDs:

SUBNET=$(aws ec2 describe-subnets --filters Name=vpc-id,Values=${RDS_VPC_ID} Name=mapPublicIpOnLaunch,Values=false --query 'Subnets[*].SubnetId' --region us-east-1 --output json)

## Create subnet group

# aws rds create-db-subnet-group --db-subnet-group-name robotshop-mysql-subnet-group --db-subnet-group-description "robotsho pmysql subnet group" --subnet-ids $SUBNET --region us-east-1
aws rds create-db-subnet-group -cli-input-json "{\"DBSubnetGroupName\":\"robotshop-mysql-subnet-group\",\"DBSubnetGroupDescription\":\"robotsho pmysql subnet group\",\"SubnetIds\":$SUBNET}" --region us-east-1

######## Create mysql db 

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
  --db-subnet-group-name "robotshopmysql-subnet-group" \
  --backup-retention-period 0 \
  --region us-east-1 \
  --port 3306 
 
## GET DB endpoint
export MYSQL_HOST=$(aws rds describe-db-instances --db-instance-identifier robotshopmysql --region us-east-1 --query 'DBInstances[*].Endpoint.Address' --output text)

###### DocumentDB

## create subnet group

aws docdb create-db-subnet-group --cli-input-json "{\"DBSubnetGroupName\":\"robotshop-docdb-subnet-group\",\"DBSubnetGroupDescription\":\"robotshop docdb subnet group\",\"SubnetIds\":$SUBNET}" --region us-east-1

## documentDB Parameter Group
# This should be one time because we don't need to clean up it every-time
# # Create
# aws docdb create-db-cluster-parameter-group \
#  --db-cluster-parameter-group-name tls-disabled-docdb50-parameter-group \
#  --db-parameter-group-family docdb5.0 \
#  --description "Custom docdb5.0 parameter group where TLS is disabled"

# # Modify
# aws docdb modify-db-cluster-parameter-group \
#     --db-cluster-parameter-group-name tls-disabled-docdb50-parameter-group \
#     --parameters "ParameterName=tls,ParameterValue=disabled,ApplyMethod=pending-reboot"

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

aws docdb create-db-instance \
  --db-instance-identifier robotshopdocdb-instance \
  --db-instance-class db.t3.medium \
  --engine docdb \
  --db-cluster-identifier robotshopdocdb-cluster \
  --region us-east-1

aws docdb wait db-instance-available --db-instance-identifier robotshopdocdb-instance --region us-east-1

export MONGODB_HOST=$(aws docdb describe-db-clusters --db-cluster-identifier robotshopdocdb-cluster --region us-east-1 --query 'DBClusters[*].Endpoint' --output text)