SCENARIO_TIMEOUT=2m
AWS_REGION=us-east-1

echo "Reducing Database max_connection..."

aws rds modify-db-parameter-group \
    --db-parameter-group-name sre-stack-mysql57 \
    --parameters "ParameterName=max_connections,ParameterValue=10,ApplyMethod=immediate" \
    --region ${AWS_REGION} \
    --no-cli-pager

sleep $SCENARIO_TIMEOUT

echo "\n Undo Database max_connection..."

aws rds modify-db-parameter-group \
    --db-parameter-group-name sre-stack-mysql57 \
    --parameters "ParameterName=max_connections,ParameterValue='{DBInstanceClassMemory/12582880}',ApplyMethod=immediate" \
    --region ${AWS_REGION} \
    --no-cli-pager
