// This bicep files deploys one resource group with the following resources:
// 1. The AI Foundry dependencies, such as VNet and
//    private endpoints for AI Search, Azure Storage and Cosmos DB
// 2. The AI Foundry itself
// 3. Two AI Projects with the capability hosts - in Foundry Standard mode
targetScope = 'resourceGroup'

param location string = resourceGroup().location

@export()
type apiType = {
  name: string
  resourceId: string
  type: string
  dnsZoneName: string // The DNS zone name for the private endpoint
}

param externalApis apiType[] = [] // Array of external API definitions

var resourceToken = toLower(uniqueString(resourceGroup().id, location))

// vnet doesn't have to be in the same RG as the AI Services
// each foundry needs it's own delegated subnet, projects inside of one Foundry share the subnet for the Agents Service
module vnet './modules/networking/vnet.bicep' = {
  name: 'vnet'
  params: {
    vnetName: 'project-vnet-${resourceToken}'
    location: location
  }
}

module ai_dependencies './modules/ai/ai-dependencies-with-dns.bicep' = {
  name: 'ai-dependencies-with-dns'
  params: {
    peSubnetName: vnet.outputs.peSubnetName
    vnetResourceId: vnet.outputs.virtualNetworkId
    resourceToken: resourceToken
    aiServicesName: '' // create AI serviced PE later
    aiAccountNameResourceGroupName: ''
  }
}

// --------------------------------------------------------------------------------------------------------------
// -- Log Analytics Workspace and App Insights ------------------------------------------------------------------
// --------------------------------------------------------------------------------------------------------------
module logAnalytics './modules/monitor/loganalytics.bicep' = {
  name: 'log-analytics'
  params: {
    newLogAnalyticsName: 'log-analytics'
    newApplicationInsightsName: 'app-insights'
    location: location
  }
}

module foundry './modules/ai/ai-foundry.bicep' = {
  name: 'foundry-deployment'
  params: {
    managedIdentityId: '' // Use System Assigned Identity
    name: 'ai-foundry-${resourceToken}'
    location: location
    appInsightsId: logAnalytics.outputs.applicationInsightsId
    publicNetworkAccess: 'Enabled'
    agentSubnetId: vnet.outputs.agentSubnetId // Use the first agent subnet
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
  name: 'ai-project-1-with-caphost-${resourceToken}'
  params: {
    foundryName: foundry.outputs.name
    location: location
    projectId: 1
    aiDependencies: ai_dependencies.outputs.aiDependencies
  }
}

module project2 './modules/ai/ai-project-with-caphost.bicep' = {
  name: 'ai-project-2-with-caphost-${resourceToken}'
  params: {
    foundryName: foundry.outputs.name
    location: location
    projectId: 2
    aiDependencies: ai_dependencies.outputs.aiDependencies
  }
  dependsOn: [
    project1 // Ensure project1 is created before project2
  ]
}

module dnsSites 'br/public:avm/res/network/private-dns-zone:0.7.1' = {
  name: 'dns-sites'
  params: {
    name: 'privatelink.azurewebsites.net'
    virtualNetworkLinks: [
      {
        virtualNetworkResourceId: vnet.outputs.virtualNetworkId
      }
    ]
  }
}

module dnsAca 'br/public:avm/res/network/private-dns-zone:0.7.1' = {
  name: 'dns-aca'
  params: {
    name: 'privatelink.${location}.azurecontainerapps.io'
    virtualNetworkLinks: [
      {
        virtualNetworkResourceId: vnet.outputs.virtualNetworkId
      }
    ]
  }
}

var dnsZones = {
  'privatelink.azurewebsites.net': dnsSites.outputs.resourceId
  'privatelink.${location}.azurecontainerapps.io': dnsAca.outputs.resourceId
}

// private endpoints for external APIs
module privateEndpoints './modules/networking/private-endpoint.bicep' = [
  for (api, index) in externalApis: {
    name: 'private-endpoint-${api.name}'
    params: {
      privateEndpointName: 'pe-${api.name}'
      location: location
      subnetId: vnet.outputs.peSubnetId // Use the private endpoint subnet
      targetResourceId: api.resourceId
      groupIds: [api.type] // Use the type as group ID
      zoneConfigs: [
        {
          name: api.dnsZoneName
          privateDnsZoneId: dnsZones[api.dnsZoneName]
        }
      ]
    }
  }
]

output capability1HostUrl string = project1.outputs.capabilityHostUrl
output capability2HostUrl string = project2.outputs.capabilityHostUrl
output ai1ConnectionUrl string = project1.outputs.aiConnectionUrl
output ai2ConnectionUrl string = project2.outputs.aiConnectionUrl
output foundry1_connection_string string = project1.outputs.foundry_connection_string
output foundry2_connection_string string = project2.outputs.foundry_connection_string
