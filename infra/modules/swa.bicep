targetScope = 'resourceGroup'

param environmentName string
param ghaDeployerPrincipalId string
param staticWebAppLocation string = 'westeurope'

var staticWebAppName = 'swa-${environmentName}'
var staticWebAppsContributorRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '554bd744-a2ac-4c1b-8f29-cd6d120cee34')

resource staticWebApp 'Microsoft.Web/staticSites@2023-12-01' = {
  name: staticWebAppName
  location: staticWebAppLocation
  sku: {
    name: 'Standard'
    tier: 'Standard'
  }
  properties: {}
}

resource ghaStaticWebAppsContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: staticWebApp
  name: guid(staticWebApp.id, 'id-gha-deployer', staticWebAppsContributorRoleDefinitionId)
  properties: {
    principalId: ghaDeployerPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: staticWebAppsContributorRoleDefinitionId
  }
}

output staticWebAppName string = staticWebApp.name
output staticWebAppDefaultHostname string = staticWebApp.properties.defaultHostname
