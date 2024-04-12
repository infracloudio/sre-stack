#!/bin/bash

GIT_TLD=`git rev-parse --show-toplevel`
source ${GIT_TLD}/.env

aws rds describe-db-instances --db-instance-identifier ${RDS_MYSQL_DB_NAME} --region ${AWS_REGION} --no-cli-pager > /dev/null 2>&1

# If the DB instance exists, delete it and wait for deletion
if [ $? -eq 0 ]; then
    aws rds delete-db-instance --db-instance-identifier ${RDS_MYSQL_DB_NAME} --skip-final-snapshot --region ${AWS_REGION} --no-cli-pager
    aws rds wait db-instance-deleted --db-instance-identifier ${RDS_MYSQL_DB_NAME} --region ${AWS_REGION} --no-cli-pager

else
    echo "${RDS_MYSQL_DB_NAME} DB does not exist."
fi

CHECK_RDS_SUBNET_GROUP_EXISTS=$(aws rds describe-db-subnet-groups \
    --db-subnet-group-name ${RDS_MYSQL_DB_SUBNET_GROUP_NAME} \
    --region ${AWS_REGION} \
    --query 'DBSubnetGroups[0].DBSubnetGroupName' \
    --output text \
    --no-cli-pager 2>/dev/null
)

# If the DB subnet group does exist, delete it
if [ -n "$CHECK_RDS_SUBNET_GROUP_EXISTS" ]; then
    echo "Deleting MySQL DB subnet group ${RDS_MYSQL_DB_SUBNET_GROUP_NAME}"
    # Delete the DB subnet group
    aws rds delete-db-subnet-group --db-subnet-group-name ${RDS_MYSQL_DB_SUBNET_GROUP_NAME} --region ${AWS_REGION} --no-cli-pager
else
    echo "MySQL DB subnet group ${RDS_MYSQL_DB_SUBNET_GROUP_NAME} does not exists."
fi


