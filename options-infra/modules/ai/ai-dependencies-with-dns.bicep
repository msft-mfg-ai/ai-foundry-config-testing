param location string = resourceGroup().location
param resourceToken string
param aiServicesName string
param aiAccountNameResourceGroupName string

param vnetResourceId string
param peSubnetName string

var vnetParts = split(vnetResourceId, '/')
var vnetSubscriptionId = vnetParts[2]
var vnetResourceGroupName = vnetParts[4]
var existingVnetName = last(vnetParts)
var vnetName = trim(existingVnetName)
var azureStorageName = 'projstorage${resourceToken}'
var aiSearchName = 'project-search-${resourceToken}'
var cosmosDBName = 'project-cosmosdb-${resourceToken}'

module ai_dependencies '../ai-dependencies/standard-dependent-resources.bicep' = {
  params: {
    location: location
    azureStorageName: azureStorageName
    aiSearchName: aiSearchName
    cosmosDBName: cosmosDBName

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
module privateEndpointAndDNS '../networking/private-endpoint-and-dns.bicep' = {
  name: 'private-endpoints-and-dns'
  params: {
    aiAccountName: aiServicesName // AI Services to secure
    aiAccountNameResourceGroup: aiAccountNameResourceGroupName
    aiSearchName: ai_dependencies.outputs.aiSearchName // AI Search to secure
    storageName: ai_dependencies.outputs.azureStorageName // Storage to secure
    cosmosDBName: ai_dependencies.outputs.cosmosDBName
    vnetName: vnetName // VNet containing subnets
    peSubnetName: peSubnetName // Subnet for private endpoints
    suffix: resourceToken // Unique identifier
    vnetResourceGroupName: vnetResourceGroupName // Resource Group for the VNet
    vnetSubscriptionId: vnetSubscriptionId // Subscription ID for the VNet
    cosmosDBSubscriptionId: ai_dependencies.outputs.cosmosDBSubscriptionId // Subscription ID for Cosmos DB
    cosmosDBResourceGroupName: ai_dependencies.outputs.cosmosDBResourceGroupName // Resource Group for Cosmos DB
    aiSearchSubscriptionId: ai_dependencies.outputs.aiSearchServiceSubscriptionId // Subscription ID for AI Search Service
    aiSearchResourceGroupName: ai_dependencies.outputs.aiSearchServiceResourceGroupName // Resource Group for AI Search Service
    storageAccountResourceGroupName: ai_dependencies.outputs.azureStorageResourceGroupName // Resource Group for Storage Account
    storageAccountSubscriptionId: ai_dependencies.outputs.azureStorageSubscriptionId // Subscription ID for Storage Account
  }
}

output aiSearchName string = ai_dependencies.outputs.aiSearchName
output aiSearchResourceId string = ai_dependencies.outputs.aiSearchID
output aiSearchResourceGroupName string = ai_dependencies.outputs.aiSearchServiceResourceGroupName
output aiSearchSubscriptionId string = ai_dependencies.outputs.aiSearchServiceSubscriptionId

output azureStorageName string = ai_dependencies.outputs.azureStorageName
output azureStorageId string = ai_dependencies.outputs.azureStorageId
output azureStorageResourceGroupName string = ai_dependencies.outputs.azureStorageResourceGroupName
output azureStorageSubscriptionId string = ai_dependencies.outputs.azureStorageSubscriptionId

output cosmosDBName string = ai_dependencies.outputs.cosmosDBName
output cosmosDBId string = ai_dependencies.outputs.cosmosDBId
output cosmosDBResourceGroupName string = ai_dependencies.outputs.cosmosDBResourceGroupName
output cosmosDBSubscriptionId string = ai_dependencies.outputs.cosmosDBSubscriptionId
