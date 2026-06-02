targetScope = 'resourceGroup'

module policy '../modules/policy.bicep' = {
  name: 'policy-test'
  params: {
    environmentName: 'test'
  }
}

output assignmentName string = policy.outputs.assignmentName
