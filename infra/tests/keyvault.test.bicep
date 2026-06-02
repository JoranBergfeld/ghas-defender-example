targetScope = 'resourceGroup'

module keyVault '../modules/keyvault.bicep' = {
  name: 'keyvault-test'
  params: {
    backendPrincipalId: '00000000-0000-0000-0000-000000000002'
    developerPrincipalId: '00000000-0000-0000-0000-000000000001'
    environmentName: 'test'
    keyVaultPrivateDnsZoneId: '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net'
    location: 'westeurope'
    privateEndpointSubnetId: '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/snet-pe'
  }
}

output keyVaultName string = keyVault.outputs.keyVaultName
