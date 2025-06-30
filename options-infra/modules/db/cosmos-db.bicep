param name string
param location string = resourceGroup().location
param tags object = {}
param managedIdentityId string

@description('The name for the database')
param databaseName string = 'ai-foundry-db'

@description('The throughput policy for the database shared across containers')
@allowed([
  'Manual'
  'Autoscale'
])
param throughputPolicy string = 'Autoscale'

@description('Throughput value when using Manual Throughput Policy for the database')
@minValue(400)
@maxValue(1000000)
param manualProvisionedThroughput int = 400

@description('Maximum throughput when using Autoscale Throughput Policy for the database')
@minValue(1000)
@maxValue(1000000)
param autoscaleMaxThroughput int = 4000

@description('Enable public network access')
@allowed([
  'Enabled'
  'Disabled'
])
param publicNetworkAccess string = 'Enabled'

@description('Whether to enable serverless for this account. Cannot be used with provisioned throughput.')
param enableServerless bool = false

@description('Describes the IP address to allow access to the Cosmos DB account')
param myIpAddress string = ''

// Variables
var accountName = name
var consistencyPolicy = {
  defaultConsistencyLevel: 'Session'
}

var locations = [
  {
    locationName: location
    failoverPriority: 0
    isZoneRedundant: false
  }
]

var throughputPolicyObj = throughputPolicy == 'Manual' ? {
  throughput: manualProvisionedThroughput
} : {
  autoscaleSettings: {
    maxThroughput: autoscaleMaxThroughput
  }
}

// IP firewall rules
var ipRules = empty(myIpAddress) ? [] : [
  {
    ipAddressOrRange: myIpAddress
  }
]

// Cosmos DB Account
resource cosmosAccount 'Microsoft.DocumentDB/databaseAccounts@2024-05-15' = {
  name: accountName
  location: location
  tags: tags
  kind: 'GlobalDocumentDB'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentityId}': {}
    }
  }
  properties: {
    consistencyPolicy: consistencyPolicy
    locations: locations
    databaseAccountOfferType: 'Standard'
    enableAutomaticFailover: false
    enableMultipleWriteLocations: false
    publicNetworkAccess: publicNetworkAccess
    enableFreeTier: false
    capabilities: enableServerless ? [
      {
        name: 'EnableServerless'
      }
    ] : []
    ipRules: ipRules
    networkAclBypass: 'AzureServices'
    networkAclBypassResourceIds: []
    // Security settings for AI Foundry
    disableKeyBasedMetadataWriteAccess: false
    enableAnalyticalStorage: false
    analyticalStorageConfiguration: {
      schemaType: 'WellDefined'
    }
  }
}

// Database
resource cosmosDatabase 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2024-05-15' = {
  parent: cosmosAccount
  name: databaseName
  properties: enableServerless ? {
    resource: {
      id: databaseName
    }
  } : {
    resource: {
      id: databaseName
    }
    options: throughputPolicyObj
  }
}

// Container for AI Foundry threads - each requires 1000 RU/s minimum
resource threadsContainer 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2024-05-15' = {
  parent: cosmosDatabase
  name: 'threads'
  properties: {
    resource: {
      id: 'threads'
      partitionKey: {
        paths: [
          '/threadId'
        ]
        kind: 'Hash'
      }
      indexingPolicy: {
        indexingMode: 'consistent'
        automatic: true
        includedPaths: [
          {
            path: '/*'
          }
        ]
        excludedPaths: [
          {
            path: '/"_etag"/?'
          }
        ]
      }
      defaultTtl: -1
    }
    options: enableServerless ? {} : {
      throughput: 1000
    }
  }
}

// Container for AI Foundry messages - each requires 1000 RU/s minimum
resource messagesContainer 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2024-05-15' = {
  parent: cosmosDatabase
  name: 'messages'
  properties: {
    resource: {
      id: 'messages'
      partitionKey: {
        paths: [
          '/threadId'
        ]
        kind: 'Hash'
      }
      indexingPolicy: {
        indexingMode: 'consistent'
        automatic: true
        includedPaths: [
          {
            path: '/*'
          }
        ]
        excludedPaths: [
          {
            path: '/"_etag"/?'
          }
        ]
      }
      defaultTtl: -1
    }
    options: enableServerless ? {} : {
      throughput: 1000
    }
  }
}

// Container for AI Foundry runs - each requires 1000 RU/s minimum
resource runsContainer 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2024-05-15' = {
  parent: cosmosDatabase
  name: 'runs'
  properties: {
    resource: {
      id: 'runs'
      partitionKey: {
        paths: [
          '/threadId'
        ]
        kind: 'Hash'
      }
      indexingPolicy: {
        indexingMode: 'consistent'
        automatic: true
        includedPaths: [
          {
            path: '/*'
          }
        ]
        excludedPaths: [
          {
            path: '/"_etag"/?'
          }
        ]
      }
      defaultTtl: -1
    }
    options: enableServerless ? {} : {
      throughput: 1000
    }
  }
}

// Outputs
output id string = cosmosAccount.id
output name string = cosmosAccount.name
output endpoint string = cosmosAccount.properties.documentEndpoint
output primaryKey string = cosmosAccount.listKeys().primaryMasterKey
output secondaryKey string = cosmosAccount.listKeys().secondaryMasterKey
output connectionString string = 'AccountEndpoint=${cosmosAccount.properties.documentEndpoint};AccountKey=${cosmosAccount.listKeys().primaryMasterKey};'
output databaseName string = cosmosDatabase.name
