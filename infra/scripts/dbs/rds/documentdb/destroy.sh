#!/bin/bash

## Clean DocumentDB...
GIT_TLD=`git rev-parse --show-toplevel`
source ${GIT_TLD}/.env
aws docdb delete-db-instance --db-instance-identifier robotshopdocdb-instance --region ${AWS_REGION} --no-cli-pager
aws docdb wait db-instance-deleted --db-instance-identifier robotshopdocdb-instance --region ${AWS_REGION} --no-cli-pager
aws docdb delete-db-cluster --db-cluster-identifier robotshopdocdb-cluster --skip-final-snapshot --region ${AWS_REGION} --no-cli-pager

sleep 60

aws docdb delete-db-subnet-group --db-subnet-group-name robotshop-docdb-subnet-group --region ${AWS_REGION} --no-cli-pager



