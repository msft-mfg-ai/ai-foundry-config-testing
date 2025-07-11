targetScope = 'subscription'

param location string
param applicationName string = 'my-app'
var resourceGroupName = '${applicationName}-rg'
var foundryDependenciesResourceGroupName = '${applicationName}-foundry-dependencies-rg'

@description('The resource ID of the existing Ai resource - Azure Open AI, AI Services or AI Foundry.')
param existingAiResourceId string

@description('The Kind of AI Service, can be "AzureOpenAI" or "AIServices". For AI Foundry use AI Services. Its not recommended to use Azure OpenAI resource, since that only provided access to OpenAI models.')
@allowed([
  'AzureOpenAI'
  'AIServices'
])
param existingAiResourceKind string = 'AIServices' // Can be 'AzureOpenAI' or 'AIServices'

@description('The name of the project capability host to be created')
param projectCapHost string = 'caphostproj'

var resourceToken = toLower(uniqueString(resourceGroupName, subscription().subscriptionId, location))

resource appResourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: resourceGroupName
  location: location
}
resource foundryDependenciesResourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: foundryDependenciesResourceGroupName
  location: location
}

// --------------------------------------------------------------------------------------------------------------
// -- Log Analytics Workspace and App Insights ------------------------------------------------------------------
// --------------------------------------------------------------------------------------------------------------
module logAnalytics './modules/monitor/loganalytics.bicep' = {
  name: 'law'
  scope: appResourceGroup
  params: {
    newLogAnalyticsName: 'project-log-analytics'
    newApplicationInsightsName: 'project-app-insights'
    location: location
  }
}

module identity './modules/iam/identity.bicep' = {
  scope: appResourceGroup
  name: 'app-identity'
  params: {
    identityName: 'app-project-identity'
    location: location
  }
}

// vnet doesn't have to be in the same RG as the AI Services
// each agent needs it's own delegated subnet, which means we need as many subnets as agents
module vnet 'modules/networking/vnet.bicep' = {
  name: 'vnet'
  scope: foundryDependenciesResourceGroup
  params: {
    vnetName: 'project-vnet-${resourceToken}'
    location: location
  }
}

module vnet_with_dependencies './modules/ai/ai-dependencies-with-dns.bicep' = {
  name: 'vnet-with-dependencies'
  scope: foundryDependenciesResourceGroup
  params: {
    peSubnetName: vnet.outputs.peSubnetName
    vnetResourceId: vnet.outputs.virtualNetworkId
    resourceToken: resourceToken
    aiServicesName: foundry.outputs.name
    aiAccountNameResourceGroupName: appResourceGroup.name
  }
}

module foundry './modules/ai/ai-foundry.bicep' = {
  name: 'foundry'
  scope: appResourceGroup
  params: {
    managedIdentityId: identity.outputs.managedIdentityId
    name: 'ai-foundry-no-models-${resourceToken}'
    location: location
    appInsightsName: logAnalytics.outputs.applicationInsightsName
    publicNetworkAccess: 'Enabled'
    deployModels: false
    agentSubnetId: vnet.outputs.agentSubnetId
  }
}

module aiProject './modules/ai/ai-project.bicep' = {
  name: 'ai-project'
  scope: appResourceGroup
  params: {
    foundry_name: foundry.outputs.name
    location: location
    project_name: 'ai-project1'
    project_description: 'AI Project with existing, external AI resource ${existingAiResourceId}'
    display_name: 'AI Project with ${existingAiResourceKind}'
    managedIdentityId: identity.outputs.managedIdentityId
    existingAiResourceId: existingAiResourceId
    existingAiKind: existingAiResourceKind

    aiSearchName: vnet_with_dependencies.outputs.aiSearchName
    aiSearchServiceResourceGroupName: vnet_with_dependencies.outputs.aiSearchResourceGroupName
    aiSearchServiceSubscriptionId: vnet_with_dependencies.outputs.aiSearchSubscriptionId

    azureStorageName: vnet_with_dependencies.outputs.azureStorageName
    azureStorageResourceGroupName: vnet_with_dependencies.outputs.azureStorageResourceGroupName
    azureStorageSubscriptionId: vnet_with_dependencies.outputs.azureStorageSubscriptionId

    cosmosDBName: vnet_with_dependencies.outputs.cosmosDBName
    cosmosDBResourceGroupName: vnet_with_dependencies.outputs.cosmosDBResourceGroupName
    cosmosDBSubscriptionId: vnet_with_dependencies.outputs.cosmosDBSubscriptionId
  }
}

module formatProjectWorkspaceId 'modules/ai/format-project-workspace-id.bicep' = {
  name: 'format-project-workspace-id-deployment'
  scope: appResourceGroup
  params: {
    projectWorkspaceId: aiProject.outputs.projectWorkspaceId
  }
}

//Assigns the project SMI the storage blob data contributor role on the storage account

module storageAccountRoleAssignment 'modules/iam/azure-storage-account-role-assignment.bicep' = {
  name: 'storage-role-assignment-deployment'
  scope: foundryDependenciesResourceGroup
  params: {
    azureStorageName: vnet_with_dependencies.outputs.azureStorageName
    projectPrincipalId: identity.outputs.managedIdentityPrincipalId
  }
}

// The Comos DB Operator role must be assigned before the caphost is created
module cosmosAccountRoleAssignments 'modules/iam/cosmosdb-account-role-assignment.bicep' = {
  name: 'cosmos-account-ra-project-deployment'
  scope: foundryDependenciesResourceGroup
  params: {
    cosmosDBName: vnet_with_dependencies.outputs.cosmosDBName
    projectPrincipalId: identity.outputs.managedIdentityPrincipalId
  }
}

// This role can be assigned before or after the caphost is created
module aiSearchRoleAssignments 'modules/iam/ai-search-role-assignments.bicep' = {
  name: 'ai-search-ra-project-deployment'
  scope: foundryDependenciesResourceGroup
  params: {
    aiSearchName: vnet_with_dependencies.outputs.aiSearchName
    projectPrincipalId: identity.outputs.managedIdentityPrincipalId
  }
}

// This module creates the capability host for the project and account
module addProjectCapabilityHost 'modules/ai/add-project-capability-host.bicep' = {
  name: 'capabilityHost-configuration-deployment'
  scope: appResourceGroup
  params: {
    accountName: foundry.outputs.name
    projectName: aiProject.outputs.project_name
    cosmosDBConnection: aiProject.outputs.cosmosDBConnection
    azureStorageConnection: aiProject.outputs.azureStorageConnection
    aiSearchConnection: aiProject.outputs.aiSearchConnection
    aiFoundryConnectionName: aiProject.outputs.aiFoundryConnectionName
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
  scope: foundryDependenciesResourceGroup
  params: {
    aiProjectPrincipalId: identity.outputs.managedIdentityPrincipalId
    storageName: vnet_with_dependencies.outputs.azureStorageName
    workspaceId: formatProjectWorkspaceId.outputs.projectWorkspaceIdGuid
  }
  dependsOn: [
    addProjectCapabilityHost
  ]
}

// The Cosmos Built-In Data Contributor role must be assigned after the caphost is created
module cosmosContainerRoleAssignments 'modules/iam/cosmos-container-role-assignments.bicep' = {
  name: 'cosmos-ra-${resourceToken}-deployment'
  scope: foundryDependenciesResourceGroup
  params: {
    cosmosAccountName: vnet_with_dependencies.outputs.cosmosDBName
    projectWorkspaceId: formatProjectWorkspaceId.outputs.projectWorkspaceIdGuid
    projectPrincipalId: identity.outputs.managedIdentityPrincipalId
  }
  dependsOn: [
    addProjectCapabilityHost
    storageContainersRoleAssignment
  ]
}
