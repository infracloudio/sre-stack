help:
	echo "Run commnad: make rollback"
	echo "Run commnad: make set-scenario"

rollback:
	cd ../../ && make deploy-app

set-scenario:
	kubectl apply -f ./virtual-service-fault.yaml -n bookinfo-prod
