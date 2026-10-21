# List of Scenarios

Scenario 1 - [Downstream API/Application performance degradation](https://github.com/infracloudio/sre-stack/tree/main/scenarios/scenario-01)  
Scenario 2 - [Increased DB connection count](https://github.com/infracloudio/sre-stack/tree/main/scenarios/scenario-02)  
Scenario 3 - [AZ or Datacenter zone down](https://github.com/infracloudio/sre-stack/tree/main/scenarios/scenario-03)

On Azure (AKS), scenario 1's ratings errors run with `make aks-ratings-abort-start`, `make aks-ratings-abort-status` and `make aks-ratings-abort-revert` - see [infra/azure/scenario-01/README.md](../infra/azure/scenario-01/README.md). The scripts in `scenario-01/` are for EKS.

On Azure (AKS), the cart running out of memory runs with `make aks-cart-oom-start`, `make aks-cart-oom-status` and `make aks-cart-oom-revert` - see [infra/azure/scenario-02/README.md](../infra/azure/scenario-02/README.md). This is the Azure `scenario-02` folder, not the EKS "Scenario 2 - Increased DB connection count" listed above.
