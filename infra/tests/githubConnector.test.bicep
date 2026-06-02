targetScope = 'resourceGroup'

module githubConnector '../modules/githubConnector.bicep' = {
  name: 'github-connector-test'
  params: {
    environmentName: 'test'
    hierarchyIdentifier: 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
    location: 'westeurope'
  }
}

output connectorName string = githubConnector.outputs.connectorName
