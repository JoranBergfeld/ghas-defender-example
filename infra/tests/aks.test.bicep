targetScope = 'resourceGroup'

module aks '../modules/aks.bicep' = {
  name: 'aks-test'
  params: {
    aksSubnetId: '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/snet-aks'
    backendIdentityName: 'id-backend'
    environmentName: 'test'
    ghaDeployerPrincipalId: '00000000-0000-0000-0000-000000000003'
    location: 'westeurope'
    logAnalyticsWorkspaceResourceId: '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.OperationalInsights/workspaces/log-test'
  }
}

output oidcIssuerUrl string = aks.outputs.oidcIssuerUrl
