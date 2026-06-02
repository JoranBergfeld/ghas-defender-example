targetScope = 'resourceGroup'

module staticWebApp '../modules/swa.bicep' = {
  name: 'swa-test'
  params: {
    environmentName: 'test'
    ghaDeployerPrincipalId: '00000000-0000-0000-0000-000000000003'
  }
}

output staticWebAppName string = staticWebApp.outputs.staticWebAppName
