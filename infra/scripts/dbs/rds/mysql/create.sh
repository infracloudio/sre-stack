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
aws rds create-db-subnet-group --cli-input-json "{\"DBSubnetGroupName\":\"${RDS_MYSQL_DB_SUBNET_GROUP_NAME}\",\"DBSubnetGroupDescription\":\"robotshop mysql subnet group\",\"SubnetIds\":$SUBNET}" --region ${AWS_REGION} --no-cli-pager

######## Create mysql db 
echo "\nCreate MYSQL DB..."
aws rds create-db-instance \
  --db-name ${RDS_MYSQL_DB_NAME} \
  --db-instance-identifier ${RDS_MYSQL_DB_NAME} \
  --allocated-storage ${RDS_MYSQL_DB_STORAGE} \
  --db-instance-class ${RDS_MYSQL_DB_INSTANCE_CLASS} \
  --engine mysql \
  --engine-version ${RDS_MYSQL_DB_ENGINE_VERSION} \
  --master-username ${RDS_MYSQL_DB_MASTER_USERNAME} \
  --master-user-password ${RDS_MYSQL_DB_MASTER_PASSWORD} \
  --no-publicly-accessible \
  --vpc-security-group-ids ${RDS_VPC_SECURITY_GROUP_ID} \
  --db-subnet-group-name ${RDS_MYSQL_DB_SUBNET_GROUP_NAME} \
  --db-parameter-group-name ${RDS_MYSQL_DB_PARAMETER_GROUP_NAME} \
  --backup-retention-period 0 \
  --region ${AWS_REGION} \
  --tags Key=name,Value=${RDS_MYSQL_DB_NAME} \
  --port 3306 \
  --no-cli-pager

echo "\n Wait for MYSQL DB..."
aws rds wait db-instance-available --db-instance-identifier ${RDS_MYSQL_DB_NAME}  --region ${AWS_REGION} 
