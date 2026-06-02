targetScope = 'resourceGroup'

param environmentName string
param ghaDeployerPrincipalId string
param staticWebAppLocation string = 'westeurope'

var staticWebAppName = 'swa-${environmentName}'
var staticWebAppsContributorRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'de139f84-1756-47ae-9be6-808fbbe84772')

resource staticWebApp 'Microsoft.Web/staticSites@2023-12-01' = {
  name: staticWebAppName
  location: staticWebAppLocation
  tags: {
    'azd-service-name': 'frontend'
  }
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
