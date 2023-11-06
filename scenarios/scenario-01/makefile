help:
	@echo "Run commnad: make rollback"
	@echo "Run commnad for downstream outage 500 error: make set-scenario-case1"
	@echo "Run commnad for downstream outage latency: make set-scenario-case2"
	@echo "	Case-2 run command to scale: kubectl scale -n bookinfo-prod deployment ratings-v1 --replicas 2"

rollback:
	cd ../../ && make deploy-app

set-scenario-case1:
	kubectl apply -f ./virtual-service-fault.yaml -n bookinfo-prod

set-scenario-case2:
	kubectl apply -f ./ratings-probe.yaml -n bookinfo-prod
	kubectl apply -f ./ratings-vs.yaml -n bookinfo-prod
