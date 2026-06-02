targetScope = 'resourceGroup'

module network '../modules/network.bicep' = {
  name: 'network-test'
  params: {
    environmentName: 'test'
    location: 'westeurope'
  }
}

output vnetName string = network.outputs.vnetName
