#!/usr/bin/env bash

echo "Seeding is still a WIP"

MYSQL_USER="${MYSQL_USER}"
MYSQL_PASSWORD="${MYSQL_PASSWORD}"
SOURCE_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd $SOURCE_DIR

echo "Importing all seed data into DB: $DB_DEV"
for seed_file in *.sql; do
  echo "Adding file: $seed_file"
  MYSQL_PWD=$MYSQL_PASSWORD mysql -h "${MYSQL_HOST:-localhost}" -u $MYSQL_USER < $seed_file
done
