targetScope = 'subscription'

var planNames = [
  'CloudPosture'
  'Containers'
  'KeyVaults'
  'OpenSourceRelationalDatabases'
  'Arm'
]

@batchSize(1)
resource defenderPlans 'Microsoft.Security/pricings@2024-01-01' = [for planName in planNames: {
  name: planName
  properties: {
    pricingTier: 'Standard'
  }
}]

output enabledPlans array = [for (planName, i) in planNames: defenderPlans[i].name]
