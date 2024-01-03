#!/bin/bash
GIT_TLD=`git rev-parse --show-toplevel`
source ${GIT_TLD}/.env

RDS_VPC_ID=$(aws eks describe-cluster --name ${CLUSTER_NAME} --region ${AWS_REGION} --query "cluster.resourcesVpcConfig.vpcId" --output text)

echo "\nCreate security group..."
# # ## Create security group
aws ec2 create-security-group --group-name ${DB_SECURITY_GROUP_NAME} --vpc-id ${RDS_VPC_ID} --description "RobotShop RDS security group" --region ${AWS_REGION} --no-cli-pager

# # ## Get Security group ID; NOTE: This SG is shared b/w RDS and DocumentDB/MongoDB below
RDS_VPC_SECURITY_GROUP_ID=$(aws ec2 describe-security-groups --region ${AWS_REGION}  --filters Name=group-name,Values=${DB_SECURITY_GROUP_NAME} --query 'SecurityGroups[*].GroupId' --output text)

# ## Add rule in security group
CLUSTER_SG=$(aws eks describe-cluster --name ${CLUSTER_NAME} --region ${AWS_REGION} --query "cluster.resourcesVpcConfig.clusterSecurityGroupId" --output text)

## Get private subnet IDs:
SUBNET=$(aws ec2 describe-subnets --filters Name=vpc-id,Values=${RDS_VPC_ID} Name=mapPublicIpOnLaunch,Values=false --query 'Subnets[*].SubnetId' --region ${AWS_REGION} --output json)

