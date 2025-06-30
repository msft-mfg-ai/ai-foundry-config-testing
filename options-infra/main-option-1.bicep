targetScope = 'subscription'

@description('The resource group for chat app 1')
param resourceGroupName1 string = 'rg-chat-app-1'

@description('The resource group for chat app 2')
param resourceGroupName2 string = 'rg-chat-app-2'

@description('Array of resource group names for chat apps.')
param resourceGroupNames array = [
  resourceGroupName1
  resourceGroupName2
]

@description('The Azure region where resources will be deployed.')
param location string = resourceGroup().location
@description('The resource ID of the existing Azure OpenAI resource.')
param existingAoaiResourceId string = ''

var resourceToken = toLower(uniqueString(resourceGroup().id, location))

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

module aiServices './modules/ai/ai-services.bicep' = {
  name: 'ai-services'
  params: {
    managedIdentityId: identity.outputs.managedIdentityId
    name: 'ai-services-${resourceToken}'
    location: location
    publicNetworkAccess: 'enabled'
    deployments: [
      {
        name: 'gpt-35-turbo'
        model: {
          format: 'OpenAI'
          name: 'gpt-35-turbo'
          version: '0125'
        }
      }
    ]
  }
}

module oai './modules/ai/azure-oai.bicep' = {
  name: 'oai'
  params: {
    managedIdentityId: identity.outputs.managedIdentityId
    name: 'oai-${resourceToken}'
    location: location
    publicNetworkAccess: 'enabled'
    deployments: [
      {
        name: 'gpt-35-turbo'
        model: {
          format: 'OpenAI'
          name: 'gpt-35-turbo'
          version: '0125'
        }
      }
    ]
  }
}

module foundry './modules/ai/ai-foundry.bicep' = {
  name: 'foundry'
  params: {
    managedIdentityId: identity.outputs.managedIdentityId
    name: 'ai-foundry-${resourceToken}'
    location: location
    appInsightsName: logAnalytics.outputs.applicationInsightsName
    publicNetworkAccess: 'enabled'
    deployModels: false
  }
}

module aiProject './modules/ai/ai-project.bicep' = {
  name: 'ai-project'
  params: {
    foundry_name: foundry.outputs.name
    location: location
    project_name: 'ai-project-${resourceToken}'
    project_description: 'AI Project Description'
    display_name: 'AI Project Display Name'
    managedIdentityId: identity.outputs.managedIdentityId
    existingAoaiResourceId: empty(existingAoaiResourceId) ? aiServices.outputs.id : existingAoaiResourceId
  }
}

module cosmosDb './modules/db/cosmos-db.bicep' = {
  name: 'cosmos-db'
  params: {
    accountName: 'cosmos-${resourceToken}'
    location: location
    primaryRegion: location
    databaseName: 'projectDatabase'
    managedIdentityId: identity.outputs.managedIdentityId
    consistencyLevel: 'Session'
    containers: [
      {
        name: 'documents'
        partitionKey: '/partitionKey'
        throughput: 400
      }
    ]
  }
}

module privateEndpoint './modules/networking/private-endpoint.bicep' = {
  name: 'cosmos-private-endpoint'
  params: {
    name: 'pe-cosmos-${resourceToken}'
    location: location
    resourceId: cosmosDb.outputs.id
    subnetId: '/subscriptions/${subscription().subscriptionId}/resourceGroups/${resourceGroupName}/providers/Microsoft.Network/virtualNetworks/vnet-main/subnets/subnet-private-endpoints'
    groupId: 'Sql'
    privateDnsZoneId: '/subscriptions/${subscription().subscriptionId}/resourceGroups/${resourceGroupName}/providers/Microsoft.Network/privateDnsZones/privatelink.documents.azure.com'
  }
}

module storageAccount './modules/storage/storage-account.bicep' = {
  name: 'storage-account'
  params: {
    name: 'st${resourceToken}'
    location: location
    managedIdentityId: identity.outputs.managedIdentityId
    tags: {
      application: 'AI Foundry'
      environment: 'Development'
    }
    storageAccountType: 'Standard_LRS'
    kind: 'StorageV2'
    publicBlobAccess: 'Disabled'
    publicNetworkAccess: 'Enabled'
    isHnsEnabled: false
    isSftpEnabled: false
    minimumTlsVersion: 'TLS1_2'
  }
}
