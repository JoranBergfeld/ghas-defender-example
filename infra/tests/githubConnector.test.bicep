targetScope = 'resourceGroup'

module githubConnector '../modules/githubConnector.bicep' = {
  name: 'github-connector-test'
  params: {
    environmentName: 'test'
    githubOrg: 'JoranBergfeld'
    githubRepo: 'ghas-defender-example'
    location: 'westeurope'
  }
}

output connectorName string = githubConnector.outputs.connectorName
