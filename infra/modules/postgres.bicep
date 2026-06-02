targetScope = 'resourceGroup'

param environmentName string
param location string
param postgresSubnetId string
param postgresPrivateDnsZoneId string
param keyVaultName string
@secure()
param administratorPassword string = newGuid()

var serverName = 'pg-${environmentName}-${uniqueString(resourceGroup().id)}'
var databaseName = 'appdb'

resource server 'Microsoft.DBforPostgreSQL/flexibleServers@2023-06-01-preview' = {
  name: serverName
  location: location
  sku: {
    name: 'Standard_B1ms'
    tier: 'Burstable'
  }
  properties: {
    administratorLogin: 'pgadmin'
    administratorLoginPassword: administratorPassword
    authConfig: {
      activeDirectoryAuth: 'Disabled'
      passwordAuth: 'Enabled'
    }
    backup: {
      backupRetentionDays: 7
      geoRedundantBackup: 'Disabled'
    }
    highAvailability: {
      mode: 'Disabled'
    }
    network: {
      delegatedSubnetResourceId: postgresSubnetId
      privateDnsZoneArmResourceId: postgresPrivateDnsZoneId
      publicNetworkAccess: 'Disabled'
    }
    storage: {
      storageSizeGB: 32
    }
    version: '16'
  }
}

resource database 'Microsoft.DBforPostgreSQL/flexibleServers/databases@2023-06-01-preview' = {
  parent: server
  name: databaseName
  properties: {
    charset: 'UTF8'
    collation: 'en_US.utf8'
  }
}

resource uuidExtensionConfig 'Microsoft.DBforPostgreSQL/flexibleServers/configurations@2023-06-01-preview' = {
  parent: server
  name: 'azure.extensions'
  properties: {
    source: 'user-override'
    value: 'UUID-OSSP'
  }
}

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

resource postgresAdminPasswordSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'postgres-admin-password'
  properties: {
    value: administratorPassword
  }
}

output postgresServerName string = server.name
output postgresHost string = server.properties.fullyQualifiedDomainName
output databaseName string = database.name
