targetScope = 'subscription'

@description('Azd environment name. The demo environment is "demo".')
param environmentName string

@description('Azure region for regional resources. Default is westeurope.')
param location string = 'westeurope'

@description('Object ID of the signed-in user or service principal running azd provision.')
param principalId string

@description('GitHub organization or user that owns the repository.')
param githubOrg string = 'JoranBergfeld'

@description('GitHub repository name.')
param githubRepo string = 'ghas-defender-example'

var resourceGroupName = 'rg-ghas-defender-${environmentName}'
var ghaDeployerName = 'id-gha-deployer'
var readerRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'acdd72a7-3385-48ef-bd42-f606fba81ae7')

resource resourceGroup 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroupName
  location: location
}

module defender 'modules/defender.bicep' = {
  name: 'defender-${environmentName}'
  scope: subscription()
}

module network 'modules/network.bicep' = {
  name: 'network-${environmentName}'
  scope: resourceGroup
  params: {
    environmentName: environmentName
    location: location
  }
}

module logAnalytics 'modules/loganalytics.bicep' = {
  name: 'loganalytics-${environmentName}'
  scope: resourceGroup
  params: {
    environmentName: environmentName
    location: location
  }
}

module identity 'modules/identity.bicep' = {
  name: 'identity-${environmentName}'
  scope: resourceGroup
  params: {
    environmentName: environmentName
    githubOrg: githubOrg
    githubRepo: githubRepo
    location: location
  }
}

resource ghaSubscriptionReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, resourceGroupName, ghaDeployerName, readerRoleDefinitionId)
  properties: {
    principalId: identity.outputs.ghaDeployerPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: readerRoleDefinitionId
  }
}

module keyVault 'modules/keyvault.bicep' = {
  name: 'keyvault-${environmentName}'
  scope: resourceGroup
  params: {
    backendPrincipalId: identity.outputs.backendPrincipalId
    developerPrincipalId: principalId
    environmentName: environmentName
    keyVaultPrivateDnsZoneId: network.outputs.keyVaultPrivateDnsZoneId
    location: location
    privateEndpointSubnetId: network.outputs.privateEndpointSubnetId
  }
}

module aks 'modules/aks.bicep' = {
  name: 'aks-${environmentName}'
  scope: resourceGroup
  params: {
    aksSubnetId: network.outputs.aksSubnetId
    backendIdentityName: identity.outputs.backendIdentityName
    environmentName: environmentName
    ghaDeployerPrincipalId: identity.outputs.ghaDeployerPrincipalId
    location: location
    logAnalyticsWorkspaceResourceId: logAnalytics.outputs.workspaceId
  }
}

module acr 'modules/acr.bicep' = {
  name: 'acr-${environmentName}'
  scope: resourceGroup
  params: {
    backendPrincipalId: identity.outputs.backendPrincipalId
    developerPrincipalId: principalId
    environmentName: environmentName
    ghaDeployerPrincipalId: identity.outputs.ghaDeployerPrincipalId
    kubeletIdentityObjectId: aks.outputs.kubeletIdentityObjectId
    location: location
    privateEndpointSubnetId: network.outputs.privateEndpointSubnetId
    registryPrivateDnsZoneId: network.outputs.acrPrivateDnsZoneId
  }
}

module postgres 'modules/postgres.bicep' = {
  name: 'postgres-${environmentName}'
  scope: resourceGroup
  params: {
    environmentName: environmentName
    keyVaultName: keyVault.outputs.keyVaultName
    location: location
    postgresPrivateDnsZoneId: network.outputs.postgresPrivateDnsZoneId
    postgresSubnetId: network.outputs.postgresSubnetId
  }
}

module staticWebApp 'modules/swa.bicep' = {
  name: 'swa-${environmentName}'
  scope: resourceGroup
  params: {
    environmentName: environmentName
    ghaDeployerPrincipalId: identity.outputs.ghaDeployerPrincipalId
  }
}

module policy 'modules/policy.bicep' = {
  name: 'policy-${environmentName}'
  scope: resourceGroup
  params: {
    environmentName: environmentName
  }
  dependsOn: [
    aks
  ]
}

module githubConnector 'modules/githubConnector.bicep' = {
  name: 'github-connector-${environmentName}'
  scope: resourceGroup
  params: {
    environmentName: environmentName
    githubOrg: githubOrg
    githubRepo: githubRepo
    location: location
  }
}

output AZURE_RESOURCE_GROUP string = resourceGroup.name
output AZURE_LOCATION string = location
output AZURE_TENANT_ID string = tenant().tenantId
output AZURE_SUBSCRIPTION_ID string = subscription().subscriptionId
output AZURE_CONTAINER_REGISTRY_ENDPOINT string = acr.outputs.loginServer
output AZURE_CONTAINER_REGISTRY_NAME string = acr.outputs.registryName
output AZURE_AKS_CLUSTER_NAME string = aks.outputs.clusterName
output AZURE_AKS_NAMESPACE string = 'app'
output AZURE_STATIC_WEB_APP_NAME string = staticWebApp.outputs.staticWebAppName
output AZURE_KEY_VAULT_NAME string = keyVault.outputs.keyVaultName
output AZURE_KEY_VAULT_URI string = keyVault.outputs.keyVaultUri
output AZURE_POSTGRES_HOST string = postgres.outputs.postgresHost
output AZURE_POSTGRES_DATABASE string = postgres.outputs.databaseName
output AZURE_BACKEND_IDENTITY_CLIENT_ID string = identity.outputs.backendClientId
output AZURE_GHA_DEPLOYER_CLIENT_ID string = identity.outputs.ghaDeployerClientId
