targetScope = 'resourceGroup'

param environmentName string
param location string
param githubOrg string
param githubRepo string

var connectorName = 'ghas-github-${environmentName}-${uniqueString(subscription().subscriptionId, githubOrg, githubRepo)}'

resource githubConnector 'Microsoft.Security/securityConnectors@2024-08-01-preview' = {
  name: connectorName
  location: location
  kind: 'GitHub'
  properties: {
    environmentData: {
      environmentType: 'GithubScope'
    }
    environmentName: 'GitHub'
    hierarchyIdentifier: '${githubOrg}/${githubRepo}'
    offerings: [
      {
        offeringType: 'CspmMonitorGithub'
      }
    ]
  }
}

output connectorName string = githubConnector.name
output connectorId string = githubConnector.id
