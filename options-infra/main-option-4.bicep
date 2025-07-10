targetScope = 'managementGroup'

param subscriptionId string
param location string = 'westus'
param resourceGroupName string = ''

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

//Existing standard Agent required resources
@description('Existing Virtual Network name Resource ID')
param existingVnetResourceId string
@description('The name of Private Endpoint subnet to create new or existing subnet for private endpoints')
param peSubnetName string = 'pe-subnet'

@description('The name of the project capability host to be created')
param projectCapHost string = 'caphostproj'

var resourceToken = toLower(uniqueString(subscriptionId, resourceGroupName, location))

var existingVnetPassedIn = existingVnetResourceId != ''
var vnetParts = split(existingVnetResourceId, '/')
var vnetSubscriptionId = existingVnetPassedIn ? vnetParts[2] : ''
var vnetResourceGroupName = existingVnetPassedIn ? vnetParts[4] : ''
var existingVnetName = existingVnetPassedIn ? last(vnetParts) : ''
var vnetName = trim(existingVnetName)

@description('Object mapping DNS zone names to their resource group, or empty string to indicate creation')
var existingDnsZones = {
  'privatelink.services.ai.azure.com': vnetResourceGroupName
  'privatelink.openai.azure.com': vnetResourceGroupName
  'privatelink.cognitiveservices.azure.com': vnetResourceGroupName
  'privatelink.search.windows.net': vnetResourceGroupName
  'privatelink.blob.${environment().suffixes.storage}': vnetResourceGroupName
  'privatelink.documents.azure.com': vnetResourceGroupName
}

resource resourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' existing = {
  name: resourceGroupName
  scope: subscription(subscriptionId)
}

// --------------------------------------------------------------------------------------------------------------
// -- Log Analytics Workspace and App Insights ------------------------------------------------------------------
// --------------------------------------------------------------------------------------------------------------
module logAnalytics './modules/monitor/loganalytics.bicep' = {
  name: 'law'
  scope: resourceGroup
  params: {
    newLogAnalyticsName: 'project-log-analytics'
    newApplicationInsightsName: 'project-app-insights'
    location: location
  }
}

module identity './modules/iam/identity.bicep' = {
  name: 'app-identity'
  scope: resourceGroup
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
  scope: resourceGroup
  params: {
    managedIdentityId: identity.outputs.managedIdentityId
    name: 'ai-foundry-${resourceToken}'
    location: location
    appInsightsName: logAnalytics.outputs.applicationInsightsName
    publicNetworkAccess: 'Enabled'
    deployModels: false
    agentSubnetId: agentSubnetId
  }
}

module ai_dependencies 'modules/ai-dependencies/standard-dependent-resources.bicep' = {
  scope: resourceGroup
  params: {
    location: location
    azureStorageName: 'projstorage${resourceToken}'
    aiSearchName: 'project-search-${resourceToken}'
    cosmosDBName: 'project-cosmosdb-${resourceToken}'

    // AI Search Service parameters
    aiSearchResourceId: ''
    aiSearchExists: false

    // Storage Account
    azureStorageAccountResourceId: ''
    azureStorageExists: false

    // Cosmos DB Account
    cosmosDBResourceId: ''
    cosmosDBExists: false
  }
}

// Private Endpoint and DNS Configuration
// This module sets up private network access for all Azure services:
// 1. Creates private endpoints in the specified subnet
// 2. Sets up private DNS zones for each service
// 3. Links private DNS zones to the VNet for name resolution
// 4. Configures network policies to restrict access to private endpoints only
module privateEndpointAndDNS 'modules/networking/private-endpoint-and-dns.bicep' = {
    name: 'private-endpoints-and-dns'
  scope: resourceGroup
    params: {
      aiAccountName: foundry.outputs.name    // AI Services to secure
      aiSearchName: ai_dependencies.outputs.aiSearchName       // AI Search to secure
      storageName: ai_dependencies.outputs.azureStorageName        // Storage to secure
      cosmosDBName: ai_dependencies.outputs.cosmosDBName
      vnetName: vnetName    // VNet containing subnets
      peSubnetName: peSubnetName        // Subnet for private endpoints
      suffix: resourceToken                                    // Unique identifier
      vnetResourceGroupName: vnetResourceGroupName
      vnetSubscriptionId: vnetSubscriptionId // Subscription ID for the VNet
      cosmosDBSubscriptionId: ai_dependencies.outputs.cosmosDBSubscriptionId // Subscription ID for Cosmos DB
      cosmosDBResourceGroupName: ai_dependencies.outputs.cosmosDBResourceGroupName // Resource Group for Cosmos DB
      aiSearchSubscriptionId: ai_dependencies.outputs.aiSearchServiceSubscriptionId // Subscription ID for AI Search Service
      aiSearchResourceGroupName: ai_dependencies.outputs.aiSearchServiceResourceGroupName // Resource Group for AI Search Service
      storageAccountResourceGroupName: ai_dependencies.outputs.azureStorageResourceGroupName // Resource Group for Storage Account
      storageAccountSubscriptionId: ai_dependencies.outputs.azureStorageSubscriptionId // Subscription ID for Storage Account
      existingDnsZones: existingDnsZones
      existingDnsZoneSubscriptionId: vnetSubscriptionId
    }
  }

  
module aiProject './modules/ai/ai-project.bicep' = {
  name: 'ai-project'
  scope: resourceGroup
  params: {
    foundry_name: foundry.outputs.name
    location: location
    project_name: 'ai-project1'
    project_description: 'AI Project with existing, external AI resource ${existingAiResourceId}'
    display_name: 'AI Project with ${existingAiResourceKind}'
    managedIdentityId: identity.outputs.managedIdentityId
    existingAiResourceId: existingAiResourceId
    existingAiKind: existingAiResourceKind

    aiSearchName: ai_dependencies.outputs.aiSearchName
    aiSearchServiceResourceGroupName: ai_dependencies.outputs.aiSearchServiceResourceGroupName
    aiSearchServiceSubscriptionId: ai_dependencies.outputs.aiSearchServiceSubscriptionId

    azureStorageName: ai_dependencies.outputs.azureStorageName
    azureStorageResourceGroupName: ai_dependencies.outputs.azureStorageResourceGroupName
    azureStorageSubscriptionId: ai_dependencies.outputs.azureStorageSubscriptionId

    cosmosDBName: ai_dependencies.outputs.cosmosDBName
    cosmosDBResourceGroupName: ai_dependencies.outputs.cosmosDBResourceGroupName
    cosmosDBSubscriptionId: ai_dependencies.outputs.cosmosDBSubscriptionId
  }
  dependsOn: [
    privateEndpointAndDNS
  ]
}

module formatProjectWorkspaceId 'modules/ai/format-project-workspace-id.bicep' = {
  name: 'format-project-workspace-id-deployment'
  scope: resourceGroup
  params: {
    projectWorkspaceId: aiProject.outputs.projectWorkspaceId
  }
}

/*
  Assigns the project SMI the storage blob data contributor role on the storage account
*/
module storageAccountRoleAssignment 'modules/iam/azure-storage-account-role-assignment.bicep' = {
  name: 'storage-role-assignment-deployment'
  scope: resourceGroup
  params: {
    azureStorageName: ai_dependencies.outputs.azureStorageName
    projectPrincipalId: aiProject.outputs.projectPrincipalId
  }
  dependsOn: [
   privateEndpointAndDNS
  ]
}

// The Comos DB Operator role must be assigned before the caphost is created
module cosmosAccountRoleAssignments 'modules/iam/cosmosdb-account-role-assignment.bicep' = {
  name: 'cosmos-account-ra-project-deployment'
  scope: resourceGroup
  params: {
    cosmosDBName: ai_dependencies.outputs.cosmosDBName
    projectPrincipalId: aiProject.outputs.projectPrincipalId
  }
  dependsOn: [
    privateEndpointAndDNS
  ]
}

// This role can be assigned before or after the caphost is created
module aiSearchRoleAssignments 'modules/iam/ai-search-role-assignments.bicep' = {
  name: 'ai-search-ra-project-deployment'
  scope: resourceGroup
  params: {
    aiSearchName: ai_dependencies.outputs.aiSearchName
    projectPrincipalId: aiProject.outputs.projectPrincipalId
  }
  dependsOn: [
    privateEndpointAndDNS
  ]
}

// This module creates the capability host for the project and account
module addProjectCapabilityHost 'modules/ai/add-project-capability-host.bicep' = {
  name: 'capabilityHost-configuration-deployment'
  scope: resourceGroup
  params: {
    accountName: foundry.outputs.name
    projectName: aiProject.outputs.project_name
    cosmosDBConnection: aiProject.outputs.cosmosDBConnection
    azureStorageConnection: aiProject.outputs.azureStorageConnection
    aiSearchConnection: aiProject.outputs.aiSearchConnection
    projectCapHost: projectCapHost
  }
  dependsOn: [
     privateEndpointAndDNS
     cosmosAccountRoleAssignments
     storageAccountRoleAssignment
     aiSearchRoleAssignments
  ]
}

// The Storage Blob Data Owner role must be assigned after the caphost is created
module storageContainersRoleAssignment 'modules/iam/blob-storage-container-role-assignments.bicep' = {
  name: 'storage-containers-deployment'
  scope: resourceGroup
  params: {
    aiProjectPrincipalId: aiProject.outputs.projectPrincipalId
    storageName: ai_dependencies.outputs.azureStorageName
    workspaceId: formatProjectWorkspaceId.outputs.projectWorkspaceIdGuid
  }
  dependsOn: [
    addProjectCapabilityHost
  ]
}

// The Cosmos Built-In Data Contributor role must be assigned after the caphost is created
module cosmosContainerRoleAssignments 'modules/iam/cosmos-container-role-assignments.bicep' = {
  name: 'cosmos-ra-deployment'
  scope: resourceGroup
  params: {
    cosmosAccountName: ai_dependencies.outputs.cosmosDBName
    projectWorkspaceId: formatProjectWorkspaceId.outputs.projectWorkspaceIdGuid
    projectPrincipalId: aiProject.outputs.projectPrincipalId

  }
dependsOn: [
  addProjectCapabilityHost
  storageContainersRoleAssignment
  ]
}
