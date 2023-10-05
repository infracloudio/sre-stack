help:
	echo "Run commnad: make rollback"
	echo "Run commnad: make set-scenario"

rollback:
	kubectl apply -f scenarios/scenario-01/virtual-services.yaml

set-scenario:
	kubectl apply -f scenarios/scenario-01/virtual-service-latency-fault.yaml
