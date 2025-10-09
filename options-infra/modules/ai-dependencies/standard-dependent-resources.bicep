// Creates Azure dependent resources for Azure AI Agent Service standard agent setup
import * as types from '../types/types.bicep'

@description('Azure region of the deployment')
param location string

// @description('The name of the Key Vault')
// param keyvaultName string

@description('The name of the AI Search resource')
param aiSearchName string

@description('Name of the storage account')
@minLength(3)
@maxLength(24)
param azureStorageName string

@description('Name of the new Cosmos DB account')
param cosmosDBName string

@description('The AI Search Service full ARM Resource ID. This is an optional field, and if not provided, the resource will be created.')
param aiSearchResourceId string

@description('The AI Storage Account full ARM Resource ID. This is an optional field, and if not provided, the resource will be created.')
param azureStorageAccountResourceId string

@description('The Cosmos DB Account full ARM Resource ID. This is an optional field, and if not provided, the resource will be created.')
param cosmosDBResourceId string

// param aiServiceExists bool
param aiSearchExists bool
param azureStorageExists bool
param cosmosDBExists bool

var cosmosParts = split(cosmosDBResourceId, '/')

resource existingCosmosDB 'Microsoft.DocumentDB/databaseAccounts@2024-11-15' existing = if (cosmosDBExists) {
  name: cosmosParts[8]
  scope: resourceGroup(cosmosParts[2], cosmosParts[4])
}

// CosmosDB creation

var canaryRegions = ['eastus2euap', 'centraluseuap']
var cosmosDbRegion = contains(canaryRegions, location) ? 'westus' : location
resource cosmosDB 'Microsoft.DocumentDB/databaseAccounts@2024-11-15' = if(!cosmosDBExists) {
  name: cosmosDBName
  location: cosmosDbRegion
  kind: 'GlobalDocumentDB'
  properties: {
    consistencyPolicy: {
      defaultConsistencyLevel: 'Session'
    }
    disableLocalAuth: true
    enableAutomaticFailover: false
    enableMultipleWriteLocations: false
    publicNetworkAccess: 'Disabled'
    enableFreeTier: false
    locations: [
      {
        locationName: location
        failoverPriority: 0
        isZoneRedundant: false
      }
    ]
    databaseAccountOfferType: 'Standard'
  }
}

var acsParts = split(aiSearchResourceId, '/')

resource existingSearchService 'Microsoft.Search/searchServices@2024-06-01-preview' existing = if (aiSearchExists) {
  name: acsParts[8]
  scope: resourceGroup(acsParts[2], acsParts[4])
}

// AI Search creation

resource aiSearch 'Microsoft.Search/searchServices@2024-06-01-preview' = if(!aiSearchExists) {
  name: aiSearchName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    disableLocalAuth: false
    authOptions: { aadOrApiKey: { aadAuthFailureMode: 'http401WithBearerChallenge'}}
    encryptionWithCmk: {
      enforcement: 'Unspecified'
    }
    hostingMode: 'default'
    partitionCount: 1
    publicNetworkAccess: 'disabled'
    replicaCount: 1
    semanticSearch: 'disabled'
    networkRuleSet: {
      bypass: 'None'
      ipRules: []
    }
  }
  sku: {
    name: 'basic'
  }
}

var azureStorageParts = split(azureStorageAccountResourceId, '/')

resource existingAzureStorageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' existing = if (azureStorageExists) {
  name: azureStorageParts[8]
  scope: resourceGroup(azureStorageParts[2], azureStorageParts[4])
}

// Some regions doesn't support Standard Zone-Redundant storage, need to use Geo-redundant storage
param noZRSRegions array = ['southindia', 'westus']
param sku object = contains(noZRSRegions, location) ? { name: 'Standard_GRS' } : { name: 'Standard_ZRS' }

// Storage creation

resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' = if(!azureStorageExists) {
  name: azureStorageName
  location: location
  kind: 'StorageV2'
  sku: sku
  properties: {
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    publicNetworkAccess: 'Disabled'
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Deny'
      virtualNetworkRules: []
    }
    allowSharedKeyAccess: false
  }
}

var aiSearchNameFinal string = aiSearchExists ? existingSearchService.name : aiSearch.name
var aiSearchID string = aiSearchExists ? existingSearchService.id : aiSearch.id
var aiSearchServiceResourceGroupName string = aiSearchExists ? acsParts[4] : resourceGroup().name
var aiSearchServiceSubscriptionId string = aiSearchExists ? acsParts[2] : subscription().subscriptionId

var azureStorageNameFinal string = azureStorageExists ? existingAzureStorageAccount.name :  storage.name
var azureStorageId string =  azureStorageExists ? existingAzureStorageAccount.id :  storage.id
var azureStorageResourceGroupName string = azureStorageExists ? azureStorageParts[4] : resourceGroup().name
var azureStorageSubscriptionId string = azureStorageExists ? azureStorageParts[2] : subscription().subscriptionId

var cosmosDBNameFinal string = cosmosDBExists ? existingCosmosDB.name : cosmosDB.name
var cosmosDBId string = cosmosDBExists ? existingCosmosDB.id : cosmosDB.id
var cosmosDBResourceGroupName string = cosmosDBExists ? cosmosParts[4] : resourceGroup().name
var cosmosDBSubscriptionId string = cosmosDBExists ? cosmosParts[2] : subscription().subscriptionId


output aiSearchName string = aiSearchNameFinal
output aiSearchID string = aiSearchID
output aiSearchServiceResourceGroupName string = aiSearchServiceResourceGroupName
output aiSearchServiceSubscriptionId string = aiSearchServiceSubscriptionId

output azureStorageName string = azureStorageNameFinal
output azureStorageId string = azureStorageId
output azureStorageResourceGroupName string =azureStorageResourceGroupName
output azureStorageSubscriptionId string = azureStorageSubscriptionId

output cosmosDBName string = cosmosDBNameFinal
output cosmosDBId string = cosmosDBId
output cosmosDBResourceGroupName string = cosmosDBResourceGroupName
output cosmosDBSubscriptionId string = cosmosDBSubscriptionId
// output keyvaultId string = keyVault.id

output aiDependencies types.aiDependenciesType = {
  aiSearch: {
    name: aiSearchNameFinal
    resourceId: aiSearchID
    resourceGroupName: aiSearchServiceResourceGroupName
    subscriptionId: aiSearchServiceSubscriptionId
  }
  azureStorage: {
    name: azureStorageNameFinal
    resourceId: azureStorageId
    resourceGroupName: azureStorageResourceGroupName
    subscriptionId: azureStorageSubscriptionId
  }
  cosmosDB: {
    name: cosmosDBNameFinal
    resourceId: cosmosDBId
    resourceGroupName: cosmosDBResourceGroupName
    subscriptionId: cosmosDBSubscriptionId
  }
}
