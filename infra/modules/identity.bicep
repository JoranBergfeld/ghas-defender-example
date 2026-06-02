targetScope = 'resourceGroup'

param environmentName string
param location string
param githubOrg string
param githubRepo string

var ghaDeployerName = 'id-gha-deployer'
var backendName = 'id-backend'
var contributorRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c')
var githubIssuer = 'https://token.actions.githubusercontent.com'
var githubAudiences = [
  'api://AzureADTokenExchange'
]
var githubFederatedCredentials = [
  {
    name: 'gha-main'
    subject: 'repo:${githubOrg}/${githubRepo}:ref:refs/heads/main'
  }
  {
    name: 'gha-secure'
    subject: 'repo:${githubOrg}/${githubRepo}:ref:refs/heads/secure'
  }
  {
    name: 'gha-vulnerable'
    subject: 'repo:${githubOrg}/${githubRepo}:ref:refs/heads/vulnerable'
  }
  {
    name: 'gha-pull-request'
    subject: 'repo:${githubOrg}/${githubRepo}:pull_request'
  }
]

resource ghaDeployer 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: ghaDeployerName
  location: location
  tags: {
    azdEnvName: environmentName
  }
}

resource backend 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: backendName
  location: location
  tags: {
    azdEnvName: environmentName
  }
}

resource ghaContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, ghaDeployerName, contributorRoleDefinitionId)
  properties: {
    principalId: ghaDeployer.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: contributorRoleDefinitionId
  }
}

resource ghaFederatedIdentityCredentials 'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2023-01-31' = [for credential in githubFederatedCredentials: {
  parent: ghaDeployer
  name: credential.name
  properties: {
    audiences: githubAudiences
    issuer: githubIssuer
    subject: credential.subject
  }
}]

output ghaDeployerName string = ghaDeployer.name
output ghaDeployerClientId string = ghaDeployer.properties.clientId
output ghaDeployerPrincipalId string = ghaDeployer.properties.principalId
output backendIdentityName string = backend.name
output backendClientId string = backend.properties.clientId
output backendPrincipalId string = backend.properties.principalId
