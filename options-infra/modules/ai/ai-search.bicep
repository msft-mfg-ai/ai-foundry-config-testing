param name string
param location string = resourceGroup().location
param tags object = {}
param managedIdentityId string

@description('The pricing tier of the search service you want to create (for example, basic or standard).')
@allowed([
  'free'
  'basic'
  'standard'
  'standard2'
  'standard3'
  'storage_optimized_l1'
  'storage_optimized_l2'
])
param sku string = 'standard'

@description('Replicas distribute search workloads across the service. You need at least two replicas to support high availability of query workloads (not applicable to the free tier).')
@minValue(1)
@maxValue(12)
param replicaCount int = 1

@description('Partitions allow for scaling of document count as well as faster indexing by sharding your index over multiple search units.')
@allowed([
  1
  2
  3
  4
  6
  12
])
param partitionCount int = 1

@description('Applicable only for the standard3 SKU. You can set this property to enable up to 3 high density partitions that allow up to 1000 indexes, which is much higher than the maximum indexes allowed for any other SKU.')
@allowed([
  'default'
  'highDensity'
])
param hostingMode string = 'default'

@description('Network access type for the search service.')
@allowed([
  'enabled'
  'disabled'
])
param publicNetworkAccess string = 'enabled'

@description('When set to true, calls to the search service will not be permitted to utilize API keys for authentication. This cannot be set to true if dataPlaneAuthOptions are defined.')
param disableLocalAuth bool = false

@description('Describes the IP address to allow access to the Azure AI Search service')
param myIpAddress string = ''

// Variables
var searchServiceName = name
var networkAcls = {
  bypass: 'AzureServices'
  defaultAction: empty(myIpAddress) ? 'Allow' : 'Deny'
  ipRules: empty(myIpAddress) ? [] : [
    {
      value: myIpAddress
    }
  ]
}

// Azure AI Search Service
resource searchService 'Microsoft.Search/searchServices@2024-06-01-preview' = {
  name: searchServiceName
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentityId}': {}
    }
  }
  sku: {
    name: sku
  }
  properties: {
    replicaCount: replicaCount
    partitionCount: partitionCount
    hostingMode: hostingMode
    publicNetworkAccess: publicNetworkAccess
    networkRuleSet: publicNetworkAccess == 'enabled' ? networkAcls : null
    disableLocalAuth: disableLocalAuth
    authOptions: disableLocalAuth ? {
      aadOrApiKey: {
        aadAuthFailureMode: 'http401WithBearerChallenge'
      }
    } : null
    encryptionWithCmk: {
      enforcement: 'Unspecified'
    }
    semanticSearch: sku == 'free' ? 'disabled' : 'standard'
  }
}

// Outputs
output id string = searchService.id
output name string = searchService.name
output endpoint string = 'https://${searchService.name}.search.windows.net'
output primaryKey string = searchService.listAdminKeys().primaryKey
output secondaryKey string = searchService.listAdminKeys().secondaryKey
output queryKey string = searchService.listQueryKeys().value[0].key
