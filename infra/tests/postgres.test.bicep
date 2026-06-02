targetScope = 'resourceGroup'

module postgres '../modules/postgres.bicep' = {
  name: 'postgres-test'
  params: {
    environmentName: 'test'
    keyVaultName: 'kvtest1234567890'
    location: 'westeurope'
    postgresPrivateDnsZoneId: '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/privateDnsZones/privatelink.postgres.database.azure.com'
    postgresSubnetId: '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/snet-pg'
  }
}

output postgresHost string = postgres.outputs.postgresHost
