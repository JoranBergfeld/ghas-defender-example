targetScope = 'resourceGroup'

param environmentName string

var policyDefinitionId = tenantResourceId('Microsoft.Authorization/policyDefinitions', '13cd7ae3-5bc0-4ac4-a62d-4f7c120b9759')

resource denyHighSeverityVulnerableImages 'Microsoft.Authorization/policyAssignments@2024-04-01' = {
  name: 'deny-high-sev-images'
  properties: {
    description: 'Blocks Kubernetes deployments that use container images with high severity vulnerabilities reported by Microsoft Defender for Containers.'
    displayName: '[Preview] Microsoft Defender for Containers should be enabled to block container images with high severity vulnerabilities'
    enforcementMode: 'Default'
    metadata: {
      assignedBy: 'ghas-defender-example-${environmentName}'
    }
    parameters: {
      effect: {
        value: 'Deny'
      }
    }
    policyDefinitionId: policyDefinitionId
  }
}

output assignmentName string = denyHighSeverityVulnerableImages.name
