
param foundry_name string
param location string
param project_name string
param project_description string  
param display_name string
param managedIdentityId string
param tags object = {}
@description('The resource ID of the existing AI resource.')
param existingAiResourceId string
@description('The Kind of AI Service, can be "AzureOpenAI" or "AIServices"')
@allowed([
  'AzureOpenAI'
  'AIServices'
])
param existingAiKind string = 'AIServices'

var byoAiConnectionName = 'aiConnection'

// get subid, resource group name and resource name from the existing resource id
var existingAiResourceIdParts = split(existingAiResourceId, '/')
var existingAiResourceIdSubId = empty(existingAiResourceId) ? '' : existingAiResourceIdParts[2]
var existingAiResourceIdRgName = empty(existingAiResourceId) ? '' : existingAiResourceIdParts[4]
var existingAiResourceIdName = empty(existingAiResourceId) ? '' : existingAiResourceIdParts[8]

// Get the existing Azure AI resource
resource existingAiResource 'Microsoft.CognitiveServices/accounts@2023-05-01' existing = {
  scope: resourceGroup(existingAiResourceIdSubId, existingAiResourceIdRgName)
  name: existingAiResourceIdName
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
}

resource byoAoaiConnectionFoundry 'Microsoft.CognitiveServices/accounts/connections@2025-04-01-preview' = if (!empty(existingAiResourceId)) {
  name: '${byoAiConnectionName}-foundry-by-${project_name}'
  parent: foundry
  properties: {
    category: existingAiKind
    target: existingAiResource.properties.endpoint
    authType: 'AAD'
    metadata: {
      ApiType: 'Azure'
      ResourceId: existingAiResource.id
      location: existingAiResource.location
    }
  }
}

resource byoAoaiConnection 'Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview' = if (!empty(existingAiResourceId)) {
  name: '${byoAiConnectionName}-project-${project_name}'
  parent: foundry_project
  properties: {
    category: existingAiKind
    target: existingAiResource.properties.endpoint
    authType: 'AAD'
    metadata: {
      ApiType: 'Azure'
      ResourceId: existingAiResource.id
      location: existingAiResource.location
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
    aiServicesConnections: !empty(existingAiResourceId) ? ['${byoAiConnectionName}-project-${project_name}'] : []
  }
  dependsOn: [
    accountCapabilityHost
  ]
}

output project_name string = foundry_project.name
output project_id string = foundry_project.id
output projectPrincipalId string = managedIdentityId
output projectConnectionString string = 'https://${foundry_name}.services.ai.azure.com/api/projects/${project_name}'
