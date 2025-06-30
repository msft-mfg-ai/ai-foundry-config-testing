
param foundry_name string
param location string
param project_name string
param project_description string  
param display_name string
param managedIdentityId string
param tags object = {}
@description('The resource ID of the existing Azure OpenAI resource.')
param existingAoaiResourceId string = ''

var byoAoaiConnectionName = 'aoaiConnection'

// get subid, resource group name and resource name from the existing resource id
var existingAoaiResourceIdParts = split(existingAoaiResourceId, '/')
var existingAoaiResourceIdSubId = empty(existingAoaiResourceId) ? '' : existingAoaiResourceIdParts[2]
var existingAoaiResourceIdRgName = empty(existingAoaiResourceId) ? '' : existingAoaiResourceIdParts[4]
var existingAoaiResourceIdName = empty(existingAoaiResourceId) ? '' : existingAoaiResourceIdParts[8]

// Get the existing Azure OpenAI resource
resource existingAoaiResource 'Microsoft.CognitiveServices/accounts@2023-05-01' existing = if (!empty(existingAoaiResourceId)) {
  scope: resourceGroup(existingAoaiResourceIdSubId, existingAoaiResourceIdRgName)
  name: existingAoaiResourceIdName
}

#disable-next-line BCP081
resource foundry 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' existing = {
  name: foundry_name
  scope: resourceGroup()
}

#disable-next-line BCP081
resource foundry_project 'Microsoft.CognitiveServices/accounts/projects@2025-04-01-preview' = {
  parent: foundry
  name: project_name
  tags: tags
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentityId}': {}
    }
  }
  properties: {
    description: project_description
    displayName: display_name
  }

  resource byoAoaiConnection 'connections@2025-04-01-preview' = {
    name: byoAoaiConnectionName
    properties: {
      category: 'AIServices'
      target: existingAoaiResource.properties.endpoint
      authType: 'AAD'
      metadata: {
        ApiType: 'Azure'
        ResourceId: existingAoaiResource.id
        location: existingAoaiResource.location
      }
    }
  }
}

resource accountCapabilityHost 'Microsoft.CognitiveServices/accounts/capabilityHosts@2025-04-01-preview' = {
  name: '${foundry.name}-capHost'
  parent: foundry
  properties: {
    capabilityHostKind: 'Agents'
  }
  dependsOn: [
    foundry_project
  ]
}

resource projectCapabilityHost 'Microsoft.CognitiveServices/accounts/projects/capabilityHosts@2025-04-01-preview' = {
  name: '${project_name}-capHost'
  parent: foundry_project
  properties: {
    capabilityHostKind: 'Agents'
    aiServicesConnections: ['${byoAoaiConnectionName}']
  }
  dependsOn: [
    accountCapabilityHost
  ]
}

output project_name string = foundry_project.name
output project_id string = foundry_project.id
output projectPrincipalId string = managedIdentityId
output projectConnectionString string = 'https://${foundry_name}.services.ai.azure.com/api/projects/${project_name}'
