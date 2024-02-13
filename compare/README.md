Install causely 

```
causely auth login

causely agent install --cluster-name sre-stack --values causely-default-values.yaml

```


Install Dynatrace 

```
aws eks create-addon --cluster-name sre-stack --addon-name dynatrace_dynatrace-operator --addon-version v0.14.2-eksbuild.1 --region us-west-2

kubectl -n dynatrace create secret generic dynakube --from-literal="apiToken=<token>" --from-literal="dataIngestToken=<token>"

kubectl apply -f dynakube-k8s-csi.yaml

kubectl apply -f dynakube.yaml
```