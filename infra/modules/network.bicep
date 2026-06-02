targetScope = 'resourceGroup'

param environmentName string
param location string

var vnetName = 'vnet-${environmentName}'
var aksSubnetName = 'snet-aks'
var postgresSubnetName = 'snet-pg'
var privateEndpointSubnetName = 'snet-pe'
var postgresPrivateDnsZoneName = 'privatelink.postgres.database.azure.com'
var keyVaultPrivateDnsZoneName = 'privatelink.vaultcore.azure.net'
var acrPrivateDnsZoneName = 'privatelink.azurecr.io'

resource aksNsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: 'nsg-${environmentName}-aks'
  location: location
  properties: {
    securityRules: [
      {
        name: 'AllowHttpInbound'
        properties: {
          access: 'Allow'
          direction: 'Inbound'
          priority: 100
          protocol: 'Tcp'
          sourceAddressPrefix: 'Internet'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '80'
        }
      }
      {
        name: 'AllowHttpsInbound'
        properties: {
          access: 'Allow'
          direction: 'Inbound'
          priority: 110
          protocol: 'Tcp'
          sourceAddressPrefix: 'Internet'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '443'
        }
      }
    ]
  }
}

resource postgresNsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: 'nsg-${environmentName}-pg'
  location: location
  properties: {
    securityRules: []
  }
}

resource privateEndpointNsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: 'nsg-${environmentName}-pe'
  location: location
  properties: {
    securityRules: []
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.40.0.0/16'
      ]
    }
    subnets: [
      {
        name: aksSubnetName
        properties: {
          addressPrefix: '10.40.0.0/22'
          networkSecurityGroup: {
            id: aksNsg.id
          }
        }
      }
      {
        name: postgresSubnetName
        properties: {
          addressPrefix: '10.40.4.0/27'
          delegations: [
            {
              name: 'postgres-flexible-servers'
              properties: {
                serviceName: 'Microsoft.DBforPostgreSQL/flexibleServers'
              }
            }
          ]
          networkSecurityGroup: {
            id: postgresNsg.id
          }
        }
      }
      {
        name: privateEndpointSubnetName
        properties: {
          addressPrefix: '10.40.4.32/27'
          privateEndpointNetworkPolicies: 'Disabled'
          networkSecurityGroup: {
            id: privateEndpointNsg.id
          }
        }
      }
    ]
  }
}

resource postgresPrivateDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: postgresPrivateDnsZoneName
  location: 'global'
}

resource keyVaultPrivateDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: keyVaultPrivateDnsZoneName
  location: 'global'
}

resource acrPrivateDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: acrPrivateDnsZoneName
  location: 'global'
}

resource postgresPrivateDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: postgresPrivateDnsZone
  name: '${vnetName}-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnet.id
    }
  }
}

resource keyVaultPrivateDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: keyVaultPrivateDnsZone
  name: '${vnetName}-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnet.id
    }
  }
}

resource acrPrivateDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: acrPrivateDnsZone
  name: '${vnetName}-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnet.id
    }
  }
}

output vnetId string = vnet.id
output vnetName string = vnet.name
output aksSubnetId string = resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, aksSubnetName)
output postgresSubnetId string = resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, postgresSubnetName)
output privateEndpointSubnetId string = resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, privateEndpointSubnetName)
output postgresPrivateDnsZoneId string = postgresPrivateDnsZone.id
output keyVaultPrivateDnsZoneId string = keyVaultPrivateDnsZone.id
output acrPrivateDnsZoneId string = acrPrivateDnsZone.id
