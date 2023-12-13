#!/bin/bash

AWS_REGION=us-west-2

aws rds delete-db-instance --db-instance-identifier grafanapsql --skip-final-snapshot  --region ${AWS_REGION} --no-cli-pager
aws rds wait db-instance-deleted --db-instance-identifier grafanapsql  --region ${AWS_REGION} --no-cli-pager
aws rds delete-db-subnet-group --db-subnet-group-name grafana-psql-subnet-group --region ${AWS_REGION} --no-cli-pager
