targetScope = 'resourceGroup'

module identity '../modules/identity.bicep' = {
  name: 'identity-test'
  params: {
    environmentName: 'test'
    githubOrg: 'JoranBergfeld'
    githubRepo: 'ghas-defender-example'
    location: 'westeurope'
  }
}

output backendClientId string = identity.outputs.backendClientId
