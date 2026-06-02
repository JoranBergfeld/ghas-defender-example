targetScope = 'resourceGroup'

module logAnalytics '../modules/loganalytics.bicep' = {
  name: 'loganalytics-test'
  params: {
    environmentName: 'test'
    location: 'westeurope'
  }
}

output workspaceName string = logAnalytics.outputs.workspaceName
