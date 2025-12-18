param foundry_name string
param location string
param project_name string
param project_description string
param display_name string
param managedIdentityId string = ''
param tags object = {}
@description('The resource ID of the existing AI resource.')
param existingAiResourceId string?
@description('The Kind of AI Service, can be "AzureOpenAI" or "AIServices"')
@allowed([
  'AzureOpenAI'
  'AIServices'
])
param existingAiKind string = 'AIServices'

param aiSearchName string = ''
param aiSearchServiceResourceGroupName string = ''
param aiSearchServiceSubscriptionId string = ''

param cosmosDBName string = ''
param cosmosDBSubscriptionId string = ''
param cosmosDBResourceGroupName string = ''

param azureStorageName string = ''
param azureStorageSubscriptionId string = ''
param azureStorageResourceGroupName string = ''
param createHubCapabilityHost bool = false

param appInsightsId string?

// --------------------------- Application Insights resource if needed ------------------------------------------------
var insightsParts string[] = split(appInsightsId ?? '', '/')
var appInsightsName = length(insightsParts) > 0 ? insightsParts[length(insightsParts) - 1] : ''
var appInsightsResourceGroupName = length(insightsParts) > 4 ? insightsParts[4] : ''
var appInsightsSubscriptionId = length(insightsParts) > 2 ? insightsParts[2] : ''

resource appInsights 'Microsoft.Insights/components@2020-02-02' existing = if (!empty(appInsightsId)) {
  name: appInsightsName
  scope: resourceGroup(appInsightsSubscriptionId, appInsightsResourceGroupName)
}

// --------------------------------------------------------------------------------------------------------------
// split managed identity resource ID to get the name
var identityParts = split(managedIdentityId, '/')
// get the name of the managed identity
var managedIdentityName = length(identityParts) > 0 ? identityParts[length(identityParts) - 1] : ''

resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-07-31-preview' existing = if (!empty(managedIdentityName)) {
  name: managedIdentityName
}

// Agent doesn't see the models when connection is on the Foundry level
@description('Set to true to use the AI Foundry connection for the project, false to use the project connection.')
param usingFoundryAiConnection bool = false
var byoAiProjectConnectionName = 'aiConnection-project-for-${project_name}'
var byoAiFoundryConnectionName = 'aiConnection-foundry-for-${foundry_name}'

// get subid, resource group name and resource name from the existing resource id
var existingAiResourceIdParts = split(existingAiResourceId ?? '', '/')
var existingAiResourceIdSubId = empty(existingAiResourceId) ? '' : existingAiResourceIdParts[2]
var existingAiResourceIdRgName = empty(existingAiResourceId) ? '' : existingAiResourceIdParts[4]
var existingAiResourceIdName = empty(existingAiResourceId) ? '' : existingAiResourceIdParts[8]

// Get the existing Azure AI resource
resource existingAiResource 'Microsoft.CognitiveServices/accounts@2023-05-01' existing = if (!empty(existingAiResourceId)) {
  scope: resourceGroup(existingAiResourceIdSubId, existingAiResourceIdRgName)
  name: existingAiResourceIdName
}

var isAiResourceValid = empty(existingAiResourceId) || (existingAiResource!.location == location)
  ? true
  : fail('The existing AIServices resource must be in the same region as the location parameter and must exist. See: https://github.com/azure-ai-foundry/foundry-samples/tree/main/samples/microsoft/infrastructure-setup/42-basic-agent-setup-with-customization and https://learn.microsoft.com/en-us/azure/ai-foundry/agents/how-to/use-your-own-resources')

#disable-next-line BCP081
resource foundry 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' existing = {
  name: foundry_name
  scope: resourceGroup()
}

resource searchService 'Microsoft.Search/searchServices@2024-06-01-preview' existing = if (!empty(aiSearchName)) {
  name: aiSearchName
  scope: resourceGroup(aiSearchServiceSubscriptionId, aiSearchServiceResourceGroupName)
}
resource cosmosDBAccount 'Microsoft.DocumentDB/databaseAccounts@2024-12-01-preview' existing = if (!empty(cosmosDBName)) {
  name: cosmosDBName
  scope: resourceGroup(cosmosDBSubscriptionId, cosmosDBResourceGroupName)
}
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' existing = if (!empty(azureStorageName)) {
  name: azureStorageName
  scope: resourceGroup(azureStorageSubscriptionId, azureStorageResourceGroupName)
}

#disable-next-line BCP081
resource foundry_project 'Microsoft.CognitiveServices/accounts/projects@2025-04-01-preview' = {
  parent: foundry
  name: project_name
  tags: tags
  location: location
  identity: !empty(managedIdentityId)
    ? {
        type: 'UserAssigned'
        userAssignedIdentities: {
          '${managedIdentityId}': {}
        }
      }
    : {
        type: 'SystemAssigned'
      }
  properties: {
    description: project_description
    displayName: display_name
  }

    // Creates the Azure Foundry connection Application Insights
  resource connection 'connections@2025-04-01-preview' = if (!empty(appInsightsName)) {
    name: 'applicationInsights-for-${project_name}'
    properties: {
      category: 'AppInsights'
      //group: 'ServicesAndApps'  // read-only...
      target: appInsights.id
      authType: 'ApiKey'
      isSharedToAll: false
      //isDefault: true  // not valid property
      credentials: {
        key: appInsights!.properties.InstrumentationKey
      }
      metadata: {
        ApiType: 'Azure'
        ResourceId: appInsights.id
      }
    }
  }
}

resource byoAoaiConnectionFoundry 'Microsoft.CognitiveServices/accounts/connections@2025-04-01-preview' = if (!empty(existingAiResourceId) && usingFoundryAiConnection) {
  name: byoAiFoundryConnectionName
  parent: foundry
  properties: {
    category: existingAiKind
    target: existingAiResource!.properties.endpoint
    authType: 'AAD'
    metadata: {
      ApiType: 'Azure'
      ResourceId: existingAiResource.id
      location: existingAiResource!.location
    }
  }
}

resource byoAoaiConnection 'Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview' = if (!empty(existingAiResourceId) && !usingFoundryAiConnection) {
  name: byoAiProjectConnectionName
  parent: foundry_project
  properties: {
    category: existingAiKind
    target: existingAiResource!.properties.endpoint
    authType: 'AAD'
    metadata: {
      ApiType: 'Azure'
      ResourceId: existingAiResource.id
      location: existingAiResource!.location
    }
  }
}

// TODO is caphost on account level needed? This sample doesn't use it
// https://github.com/azure-ai-foundry/foundry-samples/blob/main/samples/microsoft/infrastructure-setup/15-private-network-standard-agent-setup/README.md

resource accountCapabilityHost 'Microsoft.CognitiveServices/accounts/capabilityHosts@2025-04-01-preview' = if (createHubCapabilityHost) {
  name: 'capHost'
  parent: foundry
  properties: {
    capabilityHostKind: 'Agents'
  }
  dependsOn: [
    foundry_project
  ]
}

resource project_connection_cosmosdb_account 'Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview' = if (!empty(cosmosDBName)) {
  name: '${cosmosDBName}-for-${project_name}'
  parent: foundry_project
  properties: {
    category: 'CosmosDB'
    target: cosmosDBAccount!.properties.documentEndpoint
    authType: 'AAD'
    metadata: {
      ApiType: 'Azure'
      ResourceId: cosmosDBAccount.id
      location: cosmosDBAccount!.location
    }
  }
}

resource project_connection_azure_storage 'Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview' = if (!empty(azureStorageName)) {
  name: '${azureStorageName}-for-${project_name}'
  parent: foundry_project
  properties: {
    category: 'AzureStorageAccount'
    target: storageAccount!.properties.primaryEndpoints.blob
    authType: 'AAD'
    metadata: {
      ApiType: 'Azure'
      ResourceId: storageAccount.id
      location: storageAccount!.location
    }
  }
}

resource project_connection_azureai_search 'Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview' = if (!empty(aiSearchName)) {
  name: '${aiSearchName}-for-${project_name}'
  parent: foundry_project
  properties: {
    category: 'CognitiveSearch'
    target: 'https://${aiSearchName}.search.windows.net'
    authType: 'AAD'
    metadata: {
      ApiType: 'Azure'
      ResourceId: searchService.id
      location: searchService!.location
    }
  }
}

output project_name string = foundry_project.name
output project_id string = foundry_project.id
output projectConnectionString string = 'https://${foundry_name}.services.ai.azure.com/api/projects/${project_name}'
output isAiResourceValid bool = isAiResourceValid

// return the BYO connection names
output cosmosDBConnection string = empty(cosmosDBName) ? '' : project_connection_cosmosdb_account.name
output capabilityHostName string = accountCapabilityHost.name
output azureStorageConnection string = empty(azureStorageName) ? '' : project_connection_azure_storage.name
output aiSearchConnection string = empty(aiSearchName) ? '' : project_connection_azureai_search.name
output aiFoundryConnectionName string = empty(existingAiResourceId)
  ? ''
  : usingFoundryAiConnection ? byoAiFoundryConnectionName : byoAiProjectConnectionName

#disable-next-line BCP053
output projectWorkspaceId string = foundry_project.properties.internalId

output accountPrincipalId string = empty(managedIdentityId)
  ? foundry_project.identity.principalId
  : identity!.properties.principalId
