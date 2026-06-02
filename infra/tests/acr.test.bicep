targetScope = 'resourceGroup'

module acr '../modules/acr.bicep' = {
  name: 'acr-test'
  params: {
    backendPrincipalId: '00000000-0000-0000-0000-000000000002'
    developerPrincipalId: '00000000-0000-0000-0000-000000000001'
    environmentName: 'test'
    ghaDeployerPrincipalId: '00000000-0000-0000-0000-000000000003'
    kubeletIdentityObjectId: '00000000-0000-0000-0000-000000000004'
    location: 'westeurope'
    privateEndpointSubnetId: '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/snet-pe'
    registryPrivateDnsZoneId: '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/privateDnsZones/privatelink.azurecr.io'
  }
}

output loginServer string = acr.outputs.loginServer
