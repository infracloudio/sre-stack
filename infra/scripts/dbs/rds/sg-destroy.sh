#!/bin/bash
GIT_TLD=`git rev-parse --show-toplevel`
source ${GIT_TLD}/.env
RDS_VPC_SECURITY_GROUP_ID=$(aws ec2 describe-security-groups --region ${AWS_REGION}  --filters Name=group-name,Values=RobotShopRDSSecurityGroup --query 'SecurityGroups[*].GroupId' --output text --no-cli-pager)
aws ec2 delete-security-group --group-id $RDS_VPC_SECURITY_GROUP_ID --region ${AWS_REGION} --no-cli-pager
