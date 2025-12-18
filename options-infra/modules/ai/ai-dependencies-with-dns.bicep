import * as types from '../types/types.bicep'
param location string = resourceGroup().location
param resourceToken string
param aiServicesName string
param aiAccountNameResourceGroupName string

param vnetResourceId string
param peSubnetName string

param azureStorageName string = 'projstorage${resourceToken}'
param aiSearchName string = 'project-search-${resourceToken}'
param cosmosDBName string = 'project-cosmosdb-${resourceToken}'

param azureStorageId string?
param aiSearchId string?
param cosmosDBId string?

var vnetParts = split(vnetResourceId, '/')
var vnetSubscriptionId = vnetParts[2]
var vnetResourceGroupName = vnetParts[4]
var existingVnetName = last(vnetParts)
var vnetName = trim(existingVnetName)


module ai_dependencies '../ai-dependencies/standard-dependent-resources.bicep' = {
  name: 'ai-dependencies-deployment'
  params: {
    location: location
    azureStorageName: azureStorageName
    aiSearchName: aiSearchName
    cosmosDBName: cosmosDBName

    // AI Search Service parameters
    aiSearchResourceId: aiSearchId

    // Storage Account
    azureStorageAccountResourceId: azureStorageId

    // Cosmos DB Account
    cosmosDBResourceId: cosmosDBId
  }
}

// Private Endpoint and DNS Configuration
// This module sets up private network access for all Azure services:
// 1. Creates private endpoints in the specified subnet
// 2. Sets up private DNS zones for each service
// 3. Links private DNS zones to the VNet for name resolution
// 4. Configures network policies to restrict access to private endpoints only
module privateEndpointAndDNS '../networking/private-endpoint-and-dns.bicep' = {
  name: 'private-endpoints-and-dns-deployment'
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

output DNSZones types.DnsZonesType = privateEndpointAndDNS.outputs.DNSZones
output aiDependencies types.aiDependenciesType = {
  aiSearch: {
    name: ai_dependencies.outputs.aiSearchName
    resourceId: ai_dependencies.outputs.aiSearchID
    resourceGroupName: ai_dependencies.outputs.aiSearchServiceResourceGroupName
    subscriptionId: ai_dependencies.outputs.aiSearchServiceSubscriptionId
  }
  azureStorage: {
    name: ai_dependencies.outputs.azureStorageName
    resourceId: ai_dependencies.outputs.azureStorageId
    resourceGroupName: ai_dependencies.outputs.azureStorageResourceGroupName
    subscriptionId: ai_dependencies.outputs.azureStorageSubscriptionId
  }
  cosmosDB: {
    name: ai_dependencies.outputs.cosmosDBName
    resourceId: ai_dependencies.outputs.cosmosDBId
    resourceGroupName: ai_dependencies.outputs.cosmosDBResourceGroupName
    subscriptionId: ai_dependencies.outputs.cosmosDBSubscriptionId
  }
}


