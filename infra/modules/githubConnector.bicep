targetScope = 'resourceGroup'

param environmentName string
param location string
param hierarchyIdentifier string

var connectorName = 'ghas-github-${environmentName}-${uniqueString(subscription().subscriptionId, hierarchyIdentifier)}'

resource githubConnector 'Microsoft.Security/securityConnectors@2024-08-01-preview' = {
  name: connectorName
  location: location
  kind: 'GitHub'
  properties: {
    environmentData: {
      environmentType: 'GithubScope'
    }
    environmentName: 'GitHub'
    hierarchyIdentifier: hierarchyIdentifier
    offerings: [
      {
        offeringType: 'CspmMonitorGithub'
      }
    ]
  }
}

output connectorName string = githubConnector.name
output connectorId string = githubConnector.id
