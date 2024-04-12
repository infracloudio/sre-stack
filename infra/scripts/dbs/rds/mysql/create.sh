#!/bin/bash

GIT_TLD=`git rev-parse --show-toplevel`
source ${GIT_TLD}/infra/scripts/dbs/rds/common.sh

aws ec2 authorize-security-group-ingress \
    --group-id ${RDS_VPC_SECURITY_GROUP_ID} \
    --protocol tcp \
    --port 3306 \
    --source-group ${CLUSTER_SG} \
    --region ${AWS_REGION} \
    --no-cli-pager 2>/dev/null

# Check if the DB subnet group exists
CHECK_RDS_SUBNET_GROUP_EXISTS=$(aws rds describe-db-subnet-groups \
    --db-subnet-group-name ${RDS_MYSQL_DB_SUBNET_GROUP_NAME} \
    --region ${AWS_REGION} \
    --query 'DBSubnetGroups[0].DBSubnetGroupName' \
    --output text \
    --no-cli-pager 2>/dev/null
)

# If the DB subnet group does not exist, create it
if [ -z "$CHECK_RDS_SUBNET_GROUP_EXISTS" ]; then
    echo "Creating DB subnet group ${RDS_MYSQL_DB_SUBNET_GROUP_NAME}"
    # Create the DB subnet group
    aws rds create-db-subnet-group \
        --cli-input-json "{\"DBSubnetGroupName\":\"${RDS_MYSQL_DB_SUBNET_GROUP_NAME}\",\"DBSubnetGroupDescription\":\"robotshop mysql subnet group\",\"SubnetIds\":$SUBNET}" \
        --region ${AWS_REGION} \
        --no-cli-pager
else
    echo "MySQl DB subnet group ${RDS_MYSQL_DB_SUBNET_GROUP_NAME} already exists."
fi

# Check if the parameter group exists
result=$(aws rds describe-db-parameter-groups --db-parameter-group-name "${RDS_MYSQL_DB_PARAMETER_GROUP_NAME}" --region "${AWS_REGION}" --output text --query 'DBParameterGroups[0].DBParameterGroupName' --no-cli-pager 2>/dev/null)

if [ -n "$result" ]; then
    echo "Parameter group '${RDS_MYSQL_DB_PARAMETER_GROUP_NAME}' already exists."
else
    echo "Parameter group '${RDS_MYSQL_DB_PARAMETER_GROUP_NAME}' does not exist."
    echo "Creating parameter group ${RDS_MYSQL_DB_PARAMETER_GROUP_NAME} in ${AWS_REGION}"
    aws rds create-db-parameter-group --db-parameter-group-name ${RDS_MYSQL_DB_PARAMETER_GROUP_NAME} --db-parameter-group-family ${RDS_MYSQL_DB_PARAMETER_GROUP_FAMILY} --description "sre-stack mysql rds parameter group" --no-cli-pager --region ${AWS_REGION}
fi

# Check if the MySQL DB instance already exists
CHECK_RDS_MYSQL_DB_EXISTS=$(aws rds describe-db-instances \
    --db-instance-identifier ${RDS_MYSQL_DB_NAME} \
    --query 'DBInstances[0].DBInstanceIdentifier' \
    --output text \
    --region ${AWS_REGION} \
    --no-cli-pager 2>/dev/null
)
if [ -z "$CHECK_RDS_MYSQL_DB_EXISTS" ]; then
    echo "Creating ${RDS_MYSQL_DB_NAME} MySQL DB..."
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

    echo "\nWaiting for MySQL DB..."
    aws rds wait db-instance-available --db-instance-identifier ${RDS_MYSQL_DB_NAME}  --region ${AWS_REGION} 
else
    echo "MySQL DB instance already exists: $RDS_MYSQL_DB_NAME"
fi