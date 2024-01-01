#!/bin/bash

GIT_TLD=`git rev-parse --show-toplevel`
source ${GIT_TLD}/.env

aws rds delete-db-instance --db-instance-identifier robotshopmysql --skip-final-snapshot  --region ${AWS_REGION} --no-cli-pager
aws rds wait db-instance-deleted --db-instance-identifier robotshopmysql  --region ${AWS_REGION} --no-cli-pager
aws rds delete-db-subnet-group --db-subnet-group-name robotshop-mysql-subnet-group --region ${AWS_REGION} --no-cli-pager
