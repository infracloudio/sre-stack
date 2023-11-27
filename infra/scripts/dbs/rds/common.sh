#!/bin/bash

RDS_VPC_ID=$(aws eks describe-cluster --name prod-eks-cluster --region us-east-1 --query "cluster.resourcesVpcConfig.vpcId" --output text)

echo "\nCreate security group..."
# # ## Create security group
aws ec2 create-security-group --group-name RobotShopRDSSecurityGroup --vpc-id ${RDS_VPC_ID} --description "RobotShop RDS security group" --region us-east-1 

# # ## Get Security group ID; NOTE: This SG is shared b/w RDS and DocumentDB/MongoDB below
RDS_VPC_SECURITY_GROUP_ID=$(aws ec2 describe-security-groups --region us-east-1  --filters Name=group-name,Values=RobotShopRDSSecurityGroup --query 'SecurityGroups[*].GroupId' --output text)

# ## Add rule in security group
CLUSTER_SG=$(aws eks describe-cluster --name prod-eks-cluster --region us-east-1 --query "cluster.resourcesVpcConfig.clusterSecurityGroupId" --output text)

## Get private subnet IDs:
SUBNET=$(aws ec2 describe-subnets --filters Name=vpc-id,Values=${RDS_VPC_ID} Name=mapPublicIpOnLaunch,Values=false --query 'Subnets[*].SubnetId' --region us-east-1 --output json)

