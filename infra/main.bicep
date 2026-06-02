targetScope = 'subscription'

@description('Azd environment name. The demo environment is "demo".')
param environmentName string

@description('Azure region for regional resources. Default is westeurope.')
param location string = 'westeurope'

@description('Object ID of the signed-in user or service principal running azd provision.')
param principalId string

@description('Principal type for the developer/operator role assignments — User when run by a human, ServicePrincipal when run by a CI service principal.')
@allowed([
  'User'
  'ServicePrincipal'
])
param principalType string = 'User'

@description('GitHub organization or user that owns the repository.')
param githubOrg string = 'JoranBergfeld'

@description('GitHub repository name.')
param githubRepo string = 'ghas-defender-example'

@description('Defender-assigned hierarchy identifier (GUID) for the GitHub organization. Obtained after completing the manual OAuth onboarding in the Azure portal. Leave empty to skip provisioning the GitHub security connector.')
param githubConnectorHierarchyId string = ''

@description('When true (local-first deploy) Bicep creates the Contributor and User Access Administrator role assignments needed by the gha-deployer managed identity. When false (subsequent CI runs) Bicep skips them because the same principal is already running the deployment and the assignments cannot be reconciled by name afterwards.')
param createGhaDeployerSubscriptionRoles bool = true

@description('When true (local-first deploy) Bicep creates the resource-scoped role assignments (AKS RBAC, AcrPush, KV access, SWA Contributor) for the gha-deployer managed identity. When false (CI runs) Bicep skips them — they were created during the initial local azd up and re-evaluating guid() drifts the assignment names which Azure rejects.')
param createGhaDeployerResourceRoles bool = true

@description('When true (local-first deploy) Bicep creates the developer/operator role assignments scoped to KV, ACR and AKS for the principal running azd. When false (CI runs) Bicep skips them because the CI service principal is the same identity as id-gha-deployer, so the assignments collide on principal+role+scope.')
param createDeveloperAndOperatorRoles bool = true

var resourceGroupName = 'rg-ghas-defender-${environmentName}'
var ghaDeployerName = 'id-gha-deployer'
var contributorRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c')
var userAccessAdministratorRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '18d7d88d-d35e-4fb5-a5c3-7773c20a72d9')

resource resourceGroup 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroupName
  location: location
  tags: {
    'azd-env-name': environmentName
  }
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

resource ghaSubscriptionContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (createGhaDeployerSubscriptionRoles) {
  name: guid(subscription().id, resourceGroupName, ghaDeployerName, contributorRoleDefinitionId)
  properties: {
    principalId: identity.outputs.ghaDeployerPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: contributorRoleDefinitionId
  }
}

resource ghaSubscriptionUserAccessAdmin 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (createGhaDeployerSubscriptionRoles) {
  name: guid(subscription().id, resourceGroupName, ghaDeployerName, userAccessAdministratorRoleDefinitionId)
  properties: {
    principalId: identity.outputs.ghaDeployerPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: userAccessAdministratorRoleDefinitionId
  }
}

module keyVault 'modules/keyvault.bicep' = {
  name: 'keyvault-${environmentName}'
  scope: resourceGroup
  params: {
    backendPrincipalId: identity.outputs.backendPrincipalId
    createDeveloperRole: createDeveloperAndOperatorRoles
    developerPrincipalId: principalId
    developerPrincipalType: principalType
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
    createGhaDeployerRoles: createGhaDeployerResourceRoles
    createOperatorRole: createDeveloperAndOperatorRoles
    environmentName: environmentName
    ghaDeployerPrincipalId: identity.outputs.ghaDeployerPrincipalId
    location: location
    logAnalyticsWorkspaceResourceId: logAnalytics.outputs.workspaceId
    operatorPrincipalId: principalId
    operatorPrincipalType: principalType
  }
}

module acr 'modules/acr.bicep' = {
  name: 'acr-${environmentName}'
  scope: resourceGroup
  params: {
    backendPrincipalId: identity.outputs.backendPrincipalId
    createDeveloperRole: createDeveloperAndOperatorRoles
    createGhaDeployerRoles: createGhaDeployerResourceRoles
    developerPrincipalId: principalId
    developerPrincipalType: principalType
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
    createGhaDeployerRoles: createGhaDeployerResourceRoles
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

module githubConnector 'modules/githubConnector.bicep' = if (!empty(githubConnectorHierarchyId)) {
  name: 'github-connector-${environmentName}'
  scope: resourceGroup
  params: {
    environmentName: environmentName
    hierarchyIdentifier: githubConnectorHierarchyId
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
output AZURE_STATIC_WEB_APP_HOSTNAME string = staticWebApp.outputs.staticWebAppDefaultHostname
output AZURE_KEY_VAULT_NAME string = keyVault.outputs.keyVaultName
output AZURE_KEY_VAULT_URI string = keyVault.outputs.keyVaultUri
output AZURE_POSTGRES_HOST string = postgres.outputs.postgresHost
output AZURE_POSTGRES_DATABASE string = postgres.outputs.databaseName
output AZURE_BACKEND_IDENTITY_CLIENT_ID string = identity.outputs.backendClientId
output AZURE_GHA_DEPLOYER_CLIENT_ID string = identity.outputs.ghaDeployerClientId
