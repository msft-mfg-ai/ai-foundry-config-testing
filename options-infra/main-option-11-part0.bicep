// This bicep files deploys simple foundry standard with dependencies in a different region across 3 subscriptions
// Sub 1 - AI
// Sub 2 - App
// Sub 3 - DNS
// Foundry with models - Sub 1 (AI)
// Foundry dependencies - Sub 2 (App)
// Private endpoints - Sub 1 (AI)
// DNS - Sub 3
// App VNET with peering to Foundry VNET
// ------------------
// Create main-option-10.local.bicepparam based on main-option-10.bicepparam
//
// Deploy using:
// az deployment mg create --management-group-id <name>-management-group --template-file main-option-10.bicep --parameters main-option-10.local.bicepparam -l westus
targetScope = 'managementGroup'

param foundryLocation string = 'swedencentral'
param foundrySubscriptionId string
param foundryResourceGroupName string = 'rg-ai-foundry'

param appLocation string = 'westeurope'
param appSubscriptionId string
param appResourceGroupName string = 'rg-ai-apps'

param dnsLocation string = appLocation
param dnsSubscriptionId string = appSubscriptionId
param dnsResourceGroupName string = 'rg-private-dns'

var resourceToken = toLower(uniqueString(managementGroup().id, foundryLocation))

var foundry_rg_id = '/subscriptions/${foundrySubscriptionId}/resourceGroups/${foundryResourceGroupName}'
var app_rg_id = '/subscriptions/${appSubscriptionId}/resourceGroups/${appResourceGroupName}'
var dns_rg_id = '/subscriptions/${dnsSubscriptionId}/resourceGroups/${dnsResourceGroupName}'

var tags = {
  'hidden-link:${foundry_rg_id}': 'Resource'
  'hidden-link:${app_rg_id}': 'Resource'
  'hidden-link:${dns_rg_id}': 'Resource'
  'hidden-title': 'Foundry DNS testing'
  purpose: 'Foundry DNS testing'
}

// first create resource groups for everything
module foundry_rg './modules/basic/resource-group.bicep' = {
  name: 'foundry-rg-deployment'
  scope: subscription(foundrySubscriptionId)
  params: {
    resourceGroupName: foundryResourceGroupName
    location: foundryLocation
    tags: tags
  }
}

module app_rg './modules/basic/resource-group.bicep' = {
  name: 'app-rg-deployment'
  scope: subscription(appSubscriptionId)
  params: {
    resourceGroupName: appResourceGroupName
    location: appLocation
    tags: tags
  }
}

module dns_rg './modules/basic/resource-group.bicep' = {
  name: 'dns-rg-deployment'
  scope: subscription(dnsSubscriptionId)
  params: {
    resourceGroupName: dnsResourceGroupName
    location: dnsLocation
    tags: tags
  }
}

// vnet doesn't have to be in the same RG as the AI Services
// each foundry needs it's own delegated subnet, projects inside of one Foundry share the subnet for the Agents Service
module foundry_vnet './modules/networking/vnet.bicep' = {
  name: 'foundry_vnet'
  scope: resourceGroup(foundrySubscriptionId, foundryResourceGroupName)
  params: {
    vnetName: 'foundry-vnet-${resourceToken}'
    location: foundryLocation
    vnetAddressPrefix: '172.17.0.0/22'
  }
  dependsOn: [foundry_rg]
}

module app_vnet './modules/networking/vnet-with-peering.bicep' = {
  name: 'app-vnet-deployment'
  scope: resourceGroup(appSubscriptionId, appResourceGroupName)
  params: {
    name: 'app-vnet'
    location: appLocation
    vnetAddressPrefix: '172.18.0.0/22'
    peeringResourceIds: [foundry_vnet.outputs.virtualNetworkId]
  }
  dependsOn: [app_rg]
}

module dns_zones './modules/networking/dns-zones.bicep' = {
  name: 'dns-zones-deployment'
  scope: resourceGroup(dnsSubscriptionId, dnsResourceGroupName)
  params: {
    vnetResourceIds: [
      app_vnet.outputs.virtualNetworkId
      foundry_vnet.outputs.virtualNetworkId
    ]
  }
  dependsOn: [dns_rg]
}


module ai_dependencies './modules/ai-dependencies/standard-dependent-resources.bicep' = {
  scope: resourceGroup(appSubscriptionId, appResourceGroupName)
  params: {
    location: appLocation
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
  dependsOn: [app_rg]
}

module privateEndpointAndDNS './modules/networking/private-endpoint-and-dns.bicep' = {
  name: 'private-endpoints-and-dns'
  scope: resourceGroup(foundrySubscriptionId, foundryResourceGroupName)
  params: {
    // provide existing DNS zones
    existingDnsZones: dns_zones.outputs.DNSZones

    aiAccountName: foundry.outputs.name
    aiSearchName: ai_dependencies.outputs.aiSearchName // AI Search to secure
    storageName: ai_dependencies.outputs.azureStorageName // Storage to secure
    cosmosDBName: ai_dependencies.outputs.cosmosDBName
    vnetName: foundry_vnet.outputs.virtualNetworkName
    peSubnetName: foundry_vnet.outputs.peSubnetName
    suffix: resourceToken // Unique identifier
    vnetResourceGroupName: foundry_vnet.outputs.virtualNetworkResourceGroup // Resource Group for the VNet
    vnetSubscriptionId: foundry_vnet.outputs.virtualNetworkSubscriptionId // Subscription ID for the VNet
    cosmosDBSubscriptionId: ai_dependencies.outputs.cosmosDBSubscriptionId // Subscription ID for Cosmos DB
    cosmosDBResourceGroupName: ai_dependencies.outputs.cosmosDBResourceGroupName // Resource Group for Cosmos DB
    aiSearchSubscriptionId: ai_dependencies.outputs.aiSearchServiceSubscriptionId // Subscription ID for AI Search Service
    aiSearchResourceGroupName: ai_dependencies.outputs.aiSearchServiceResourceGroupName // Resource Group for AI Search Service
    storageAccountResourceGroupName: ai_dependencies.outputs.azureStorageResourceGroupName // Resource Group for Storage Account
    storageAccountSubscriptionId: ai_dependencies.outputs.azureStorageSubscriptionId // Subscription ID for Storage Account
    aiAccountNameResourceGroup: foundry.outputs.resourceGroupName
    aiAccountSubscriptionId: foundry.outputs.subscriptionId
  }
  dependsOn: [dns_rg, foundry_rg]
}

// --------------------------------------------------------------------------------------------------------------
// -- Log Analytics Workspace and App Insights ------------------------------------------------------------------
// --------------------------------------------------------------------------------------------------------------
module logAnalytics './modules/monitor/loganalytics.bicep' = {
  scope: resourceGroup(foundrySubscriptionId, foundryResourceGroupName)
  name: 'log-analytics'
  params: {
    newLogAnalyticsName: 'log-analytics'
    newApplicationInsightsName: 'app-insights'
  }
  dependsOn: [foundry_rg]
}

module foundry './modules/ai/ai-foundry.bicep' = {
  scope: resourceGroup(foundrySubscriptionId, foundryResourceGroupName)
  name: 'ai-foundry-deployment'
  dependsOn: [foundry_rg]
  params: {
    managedIdentityId: '' // Use System Assigned Identity
    name: 'ai-foundry-models-${resourceToken}'
    appInsightsName: logAnalytics.outputs.applicationInsightsName
    publicNetworkAccess: 'Disabled'
    agentSubnetId: null // No agent subnet for Foundry with models
    deployments: [
      {
        name: 'gpt-4.1-mini'
        properties: {
          model: {
            format: 'OpenAI'
            name: 'gpt-4.1-mini'
            version: '2025-04-14'
          }
        }
        sku: {
          name: 'GlobalStandard'
          capacity: 20
        }
      }
    ]
  }
}

