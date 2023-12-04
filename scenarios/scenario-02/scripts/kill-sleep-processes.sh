#!/bin/bash

# MySQL connection details
MYSQL_USER="admin"
MYSQL_PASSWORD="docdb3421z"
MYSQL_HOST="robotshopmysql.chh4lgwsalzi.us-east-1.rds.amazonaws.com"

# Get process list IDs
PROCESS_IDS=$(MYSQL_PWD="$MYSQL_PASSWORD" mysql -h "$MYSQL_HOST" -u "$MYSQL_USER" -N -s -e "SELECT ID FROM INFORMATION_SCHEMA.PROCESSLIST WHERE USER='shipping'")

for ID in $PROCESS_IDS; do 
    MYSQL_PWD="$MYSQL_PASSWORD" mysql -h "$MYSQL_HOST" -u "$MYSQL_USER" -e "CALL mysql.rds_kill($ID)"
    echo "Terminated connection with ID $ID for user 'shipping'"
done