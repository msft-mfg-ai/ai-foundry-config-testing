param location string
@description('The resource ID of the existing Ai resource - Azure Open AI, AI Services or AI Foundry.')
param existingAiResourceId string

@description('The resource ID of the subnet where the AI Foundry agent will be deployed.')
param agentSubnetId string
@description('The Kind of AI Service, can be "AzureOpenAI" or "AIServices". For AI Foundry use AI Services. Its not recommended to use Azure OpenAI resource, since that only provided access to OpenAI models.')
@allowed([
  'AzureOpenAI'
  'AIServices'
])
param existingAiResourceKind string = 'AIServices' // Can be 'AzureOpenAI' or 'AIServices'

@description('The AI Search Service full ARM Resource ID. This is an optional field, and if not provided, the resource will be created.')
param aiSearchResourceId string
@description('The AI Storage Account full ARM Resource ID. This is an optional field, and if not provided, the resource will be created.')
param azureStorageAccountResourceId string
@description('The Cosmos DB Account full ARM Resource ID. This is an optional field, and if not provided, the resource will be created.')
param azureCosmosDBAccountResourceId string

@description('The name of the project capability host to be created')
param projectCapHost string = 'caphostproj'

var resourceToken = toLower(uniqueString(resourceGroup().name, location))

var acsParts = split(aiSearchResourceId, '/')
var aiSearchServiceSubscriptionId = acsParts[2]
var aiSearchServiceResourceGroupName = acsParts[4]
var aiSearchName = trim(last(acsParts))

var cosmosParts = split(azureCosmosDBAccountResourceId, '/')
var cosmosDBSubscriptionId = cosmosParts[2]
var cosmosDBResourceGroupName = cosmosParts[4]
var cosmosDBName = trim(last(cosmosParts))

var storageParts = split(azureStorageAccountResourceId, '/')
var azureStorageSubscriptionId = storageParts[2]
var azureStorageResourceGroupName = storageParts[4]
var azureStorageName = trim(last(storageParts))

// --------------------------------------------------------------------------------------------------------------
// -- Log Analytics Workspace and App Insights ------------------------------------------------------------------
// --------------------------------------------------------------------------------------------------------------
module logAnalytics './modules/monitor/loganalytics.bicep' = {
  name: 'law'
  params: {
    newLogAnalyticsName: 'project-log-analytics'
    newApplicationInsightsName: 'project-app-insights'
    location: location
  }
}

module identity './modules/iam/identity.bicep' = {
  name: 'app-identity'
  params: {
    identityName: 'app-project-identity'
    location: location
  }
}

// // AI Services for hosting models
// This sample uses external AI resources (from a different subscription), so the AI Services module is not used.
// NOTE: it's not recommended to use OpenAI resource, since that only provided access to OpenAI models
// module aiServices './modules/ai/ai-services.bicep' = {
//   name: 'ai-services'
//   params: {
//     managedIdentityId: identity.outputs.managedIdentityId
//     name: 'ai-services-${resourceToken}'
//     location: location
//     publicNetworkAccess: 'enabled'
//     deployments: [
//       {
//         name: 'gpt-35-turbo'
//         model: {
//           format: 'OpenAI'
//           name: 'gpt-35-turbo'
//           version: '0125'
//         }
//       }
//     ]
//   }
// }

module foundry './modules/ai/ai-foundry.bicep' = {
  name: 'foundry'
  params: {
    managedIdentityId: identity.outputs.managedIdentityId
    name: 'ai-foundry-${resourceToken}'
    location: location
    //appInsightsName: logAnalytics.outputs.applicationInsightsName
    publicNetworkAccess: 'Enabled'
    deployModels: false
    agentSubnetId: agentSubnetId
  }
}

module foundry_insights './modules/ai/foundry-insights.bicep' = {
  name: 'foundry-insights'
  params: {
    foundry_name: foundry.outputs.name
    appInsightsName: logAnalytics.outputs.applicationInsightsName
  }
}

resource storage 'Microsoft.Storage/storageAccounts@2022-05-01' existing = {
  name: azureStorageName
  scope: resourceGroup(azureStorageSubscriptionId, azureStorageResourceGroupName)
}


resource aiSearch 'Microsoft.Search/searchServices@2023-11-01' existing = {
  name: aiSearchName
  scope: resourceGroup(aiSearchServiceSubscriptionId, aiSearchServiceResourceGroupName)
}

resource cosmosDB 'Microsoft.DocumentDB/databaseAccounts@2024-11-15' existing = {
  name: cosmosDBName
  scope: resourceGroup(cosmosDBSubscriptionId, cosmosDBResourceGroupName)
}


module aiProject './modules/ai/ai-project.bicep' = {
  name: 'ai-project'
  params: {
    foundry_name: foundry.outputs.name
    location: location
    project_name: 'ai-project1'
    project_description: 'AI Project with existing, external AI resource ${existingAiResourceId}'
    display_name: 'AI Project with ${existingAiResourceKind}'
    managedIdentityId: identity.outputs.managedIdentityId
    existingAiResourceId: existingAiResourceId
    existingAiKind: existingAiResourceKind

    aiSearchName: aiSearchName
    aiSearchServiceResourceGroupName: aiSearchServiceResourceGroupName
    aiSearchServiceSubscriptionId: aiSearchServiceSubscriptionId

    azureStorageName: azureStorageName
    azureStorageResourceGroupName: azureStorageResourceGroupName
    azureStorageSubscriptionId: azureStorageSubscriptionId

    cosmosDBName: cosmosDBName
    cosmosDBResourceGroupName: cosmosDBResourceGroupName
    cosmosDBSubscriptionId: cosmosDBSubscriptionId
  }
  dependsOn: [
    storage
    aiSearch
    cosmosDB
  ]
}


module formatProjectWorkspaceId 'modules/ai/format-project-workspace-id.bicep' = {
  name: 'format-project-workspace-id-deployment'
  params: {
    projectWorkspaceId: aiProject.outputs.projectWorkspaceId
  }
}

//Assigns the project SMI the storage blob data contributor role on the storage account

module storageAccountRoleAssignment 'modules/iam/azure-storage-account-role-assignment.bicep' = {
  name: 'storage-role-assignment-deployment'
  params: {
    azureStorageName: azureStorageName
    projectPrincipalId: identity.outputs.managedIdentityPrincipalId
  }
  dependsOn: [
   storage
  ]
}

// The Comos DB Operator role must be assigned before the caphost is created
module cosmosAccountRoleAssignments 'modules/iam/cosmosdb-account-role-assignment.bicep' = {
  name: 'cosmos-account-ra-project-deployment'
  params: {
    cosmosDBName: cosmosDBName
    projectPrincipalId: identity.outputs.managedIdentityPrincipalId
  }
  dependsOn: [
    cosmosDB
  ]
}

// This role can be assigned before or after the caphost is created
module aiSearchRoleAssignments 'modules/iam/ai-search-role-assignments.bicep' = {
  name: 'ai-search-ra-project-deployment'
  params: {
    aiSearchName: aiSearchName
    projectPrincipalId: identity.outputs.managedIdentityPrincipalId
  }
  dependsOn: [
    aiSearch
  ]
}

// This module creates the capability host for the project and account
module addProjectCapabilityHost 'modules/ai/add-project-capability-host.bicep' = {
  name: 'capabilityHost-configuration-deployment'
  params: {
    accountName: foundry.outputs.name
    projectName: aiProject.outputs.project_name
    cosmosDBConnection: aiProject.outputs.cosmosDBConnection
    azureStorageConnection: aiProject.outputs.azureStorageConnection
    aiSearchConnection: aiProject.outputs.aiSearchConnection
    projectCapHost: projectCapHost
  }
  dependsOn: [
     cosmosAccountRoleAssignments
     storageAccountRoleAssignment
     aiSearchRoleAssignments
  ]
}

// The Storage Blob Data Owner role must be assigned after the caphost is created
module storageContainersRoleAssignment 'modules/iam/blob-storage-container-role-assignments.bicep' = {
  name: 'storage-containers-deployment'
  params: {
    aiProjectPrincipalId: identity.outputs.managedIdentityPrincipalId
    storageName: azureStorageName
    workspaceId: formatProjectWorkspaceId.outputs.projectWorkspaceIdGuid
  }
  dependsOn: [
    addProjectCapabilityHost
  ]
}

// The Cosmos Built-In Data Contributor role must be assigned after the caphost is created
module cosmosContainerRoleAssignments 'modules/iam/cosmos-container-role-assignments.bicep' = {
  name: 'cosmos-ra-${resourceToken}-deployment'
  params: {
    cosmosAccountName: cosmosDBName
    projectWorkspaceId: formatProjectWorkspaceId.outputs.projectWorkspaceIdGuid
    projectPrincipalId: identity.outputs.managedIdentityPrincipalId

  }
dependsOn: [
  addProjectCapabilityHost
  storageContainersRoleAssignment
  ]
}

output capabilityHostUrl string = 'https://portal.azure.com/${tenant().displayName}/resource/${aiProject.outputs.project_id}/capabilityHosts/${projectCapHost}/overview'
output aiConnectionUrl string = 'https://portal.azure.com/${tenant().displayName}/resource/${foundry.outputs.id}/connections/${aiProject.outputs.aiFoundryConnectionName}/overview'
