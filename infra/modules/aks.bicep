targetScope = 'resourceGroup'

param environmentName string
param location string
param aksSubnetId string
param logAnalyticsWorkspaceResourceId string
param ghaDeployerPrincipalId string
param operatorPrincipalId string
@allowed([
  'User'
  'ServicePrincipal'
])
param operatorPrincipalType string = 'User'
param backendIdentityName string
param createGhaDeployerRoles bool = true
param kubernetesVersion string = '1.34'

var clusterName = 'aks-${environmentName}'
var clusterUserRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4abbcc35-e782-43d8-92c5-2d3f1bd2253f')
var clusterRbacAdminRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b1ff04bb-8a4e-4dc4-8eb5-8693973ce19b')

resource cluster 'Microsoft.ContainerService/managedClusters@2024-05-01' = {
  name: clusterName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    aadProfile: {
      enableAzureRBAC: true
      managed: true
    }
    addonProfiles: {
      azurepolicy: {
        enabled: true
      }
      omsagent: {
        enabled: true
        config: {
          logAnalyticsWorkspaceResourceID: logAnalyticsWorkspaceResourceId
        }
      }
    }
    agentPoolProfiles: [
      {
        name: 'systempool'
        count: 4
        enableAutoScaling: false
        mode: 'System'
        osSKU: 'Ubuntu'
        osType: 'Linux'
        type: 'VirtualMachineScaleSets'
        vmSize: 'Standard_D2as_v6'
        vnetSubnetID: aksSubnetId
      }
    ]
    dnsPrefix: clusterName
    /*
    # SEEDED VULN #7 — see scripts/seed-vulnerabilities.md
    */
    enableRBAC: false
    ingressProfile: {
      webAppRouting: {
        enabled: true
      }
    }
    kubernetesVersion: kubernetesVersion
    networkProfile: {
      dnsServiceIP: '10.41.0.10'
      loadBalancerSku: 'standard'
      networkPlugin: 'azure'
      networkPluginMode: 'overlay'
      networkPolicy: 'azure'
      outboundType: 'loadBalancer'
      podCidr: '10.42.0.0/16'
      serviceCidr: '10.41.0.0/16'
    }
    oidcIssuerProfile: {
      enabled: true
    }
    securityProfile: {
      defender: {
        logAnalyticsWorkspaceResourceId: logAnalyticsWorkspaceResourceId
        securityMonitoring: {
          enabled: true
        }
      }
      workloadIdentity: {
        enabled: true
      }
    }
  }
}

resource ghaClusterUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (createGhaDeployerRoles) {
  scope: cluster
  name: guid(cluster.id, 'id-gha-deployer', clusterUserRoleDefinitionId)
  properties: {
    principalId: ghaDeployerPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: clusterUserRoleDefinitionId
  }
}

resource ghaClusterRbacAdmin 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (createGhaDeployerRoles) {
  scope: cluster
  name: guid(cluster.id, 'id-gha-deployer', clusterRbacAdminRoleDefinitionId)
  properties: {
    principalId: ghaDeployerPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: clusterRbacAdminRoleDefinitionId
  }
}

resource operatorClusterRbacAdmin 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: cluster
  name: guid(cluster.id, 'operator', operatorPrincipalId, clusterRbacAdminRoleDefinitionId)
  properties: {
    principalId: operatorPrincipalId
    principalType: operatorPrincipalType
    roleDefinitionId: clusterRbacAdminRoleDefinitionId
  }
}

resource backendIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  name: backendIdentityName
}

resource backendFederatedIdentityCredential 'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2023-01-31' = {
  parent: backendIdentity
  name: 'aks-app-backend'
  properties: {
    audiences: [
      'api://AzureADTokenExchange'
    ]
    issuer: cluster.properties.oidcIssuerProfile.issuerURL
    subject: 'system:serviceaccount:app:backend'
  }
}

output clusterName string = cluster.name
output oidcIssuerUrl string = cluster.properties.oidcIssuerProfile.issuerURL
output kubeletIdentityObjectId string = cluster.properties.identityProfile.kubeletidentity.objectId
