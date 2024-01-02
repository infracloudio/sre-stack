#!/bin/bash
GIT_TLD=`git rev-parse --show-toplevel`
source ${GIT_TLD}/.env

echo "Reducing Database max_connection..."

aws rds modify-db-parameter-group \
    --db-parameter-group-name ${RDS_MYSQL_DB_PARAMETER_GROUP_NAME} \
    --parameters "ParameterName=max_connections,ParameterValue=10,ApplyMethod=immediate" \
    --region ${AWS_REGION} \
    --no-cli-pager

sleep ${SCENARIO_02_TIMEOUT}

echo "\n Undo Database max_connection..."

aws rds modify-db-parameter-group \
    --db-parameter-group-name ${RDS_MYSQL_DB_PARAMETER_GROUP_NAME} \
    --parameters "ParameterName=max_connections,ParameterValue='{DBInstanceClassMemory/12582880}',ApplyMethod=immediate" \
    --region ${AWS_REGION} \
    --no-cli-pager