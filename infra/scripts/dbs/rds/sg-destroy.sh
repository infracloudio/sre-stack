#!/bin/bash
AWS_REGION=us-east-1
RDS_VPC_SECURITY_GROUP_ID=$(aws ec2 describe-security-groups --region ${AWS_REGION}  --filters Name=group-name,Values=RobotShopRDSSecurityGroup --query 'SecurityGroups[*].GroupId' --output text --no-cli-pager)
aws ec2 delete-security-group --group-id $RDS_VPC_SECURITY_GROUP_ID --region ${AWS_REGION} --no-cli-pager
