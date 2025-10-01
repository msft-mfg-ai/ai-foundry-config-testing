// This bicep files deploys simple foundry standard with dependencies in a different region
// Foundry is deployed to a VNET, all dependecies register their private endpoints in PE Subnet
targetScope = 'managementGroup'

param foundryLocation string = 'swedencentral'
param foundrySubscriptionId string
param foundryResourceGroupName string = 'rg-ai-foundry'

param appLocation string = 'westerneurope'
param appSubscriptionId string
param appResourceGroupName string = 'rg-ai-apps'

param dnsLocation string = appLocation
param dnsSubscriptionId string = appSubscriptionId
param dnsResourceGroupName string = 'rg-private-dns'


var resourceToken = toLower(uniqueString(managementGroup().id, foundryLocation))

// first create resource groups for everything
module foundry_rg './modules/basic/resource-group.bicep' = {
  name: 'foundry-rg-deployment'
  scope: subscription(foundrySubscriptionId)
  params: {
    resourceGroupName: foundryResourceGroupName
    location: foundryLocation
  }
}

module app_rg './modules/basic/resource-group.bicep' = {
  name: 'app-rg-deployment'
  scope: subscription(appSubscriptionId)
  params: {
    resourceGroupName: appResourceGroupName
    location: appLocation
  }
}

module dns_rg './modules/basic/resource-group.bicep' = {
  name: 'dns-rg-deployment'
  scope: subscription(dnsSubscriptionId)
  params: {
    resourceGroupName: dnsResourceGroupName
    location: dnsLocation
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
}

module app_vnet './modules/networking/vnet.bicep' = {
  name: 'app_vnet'
  scope: resourceGroup(appSubscriptionId, foundryResourceGroupName)
  params: {
    vnetName: 'app-vnet-${resourceToken}'
    location: foundryLocation
    vnetAddressPrefix: '172.18.0.0/22'
  }
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
}

module ai_dependencies './modules/ai-dependencies/standard-dependent-resources.bicep' = {
  scope: resourceGroup(foundrySubscriptionId, foundryResourceGroupName)
  params: {
    location: foundryLocation
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
}

module foundry './modules/ai/ai-foundry.bicep' = {
  scope: resourceGroup(foundrySubscriptionId, foundryResourceGroupName)
  name: 'foundry-shared'
  params: {
    managedIdentityId: '' // Use System Assigned Identity
    name: 'ai-foundry-${resourceToken}'
    appInsightsName: logAnalytics.outputs.applicationInsightsName
    publicNetworkAccess: 'Enabled'
    agentSubnetId: foundry_vnet.outputs.agentSubnetId // Use the first agent subnet
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

module project1 './modules/ai/ai-project-with-caphost.bicep' = {
  scope: resourceGroup(foundrySubscriptionId, foundryResourceGroupName)
  name: 'ai-project-1-with-caphost-${resourceToken}'
  params: {
    foundryName: foundry.outputs.name
    location: foundryLocation
    projectId: 1
    aiDependencies: ai_dependencies.outputs.aiDependencies
  }
}

module ai_pe './modules/networking/ai-pe-dns.bicep' = {
  name: 'ai-pe-dns-deployment'
  scope: resourceGroup(dnsSubscriptionId, dnsResourceGroupName)
  params: {
    peSubnetId: app_vnet.outputs.peSubnetId
    vnetId: app_vnet.outputs.virtualNetworkId
    resourceToken: resourceToken
    aiAccountName: foundry.outputs.name
    existingDnsZones: dns_zones.outputs.dnsZoneNames
  }
}

output capability1HostUrl string = project1.outputs.capabilityHostUrl
output ai1ConnectionUrl string = project1.outputs.aiConnectionUrl
output foundry1_connection_string string = project1.outputs.foundry_connection_string
