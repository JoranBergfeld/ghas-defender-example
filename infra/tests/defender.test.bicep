targetScope = 'subscription'

module defender '../modules/defender.bicep' = {
  name: 'defender-test'
}

output enabledPlans array = defender.outputs.enabledPlans
