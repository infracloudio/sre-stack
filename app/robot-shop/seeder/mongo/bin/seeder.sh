#!/usr/bin/env bash

echo "Seeding in progress"

SOURCE_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd $SOURCE_DIR

echo "Importing all seed data into DB: $DB_DEV"
for seed_file in *.sql; do
  echo "Adding file: $seed_file"
  #MONGO_PWD=$MONGO_PASSWORD MONGO -h "${MONGO_HOST:-localhost}" -u $MONGO_USER < $seed_file
  mongo < $seed_file
done

echo "Seeding is complete"