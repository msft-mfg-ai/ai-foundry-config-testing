// This bicep files deploys one resource group with the following resources:
// 1. The AI Foundry dependencies, such as VNet and
//    private endpoints for AI Search, Azure Storage and Cosmos DB
// 2. The AI Foundry itself
// 3. Two AI Projects with the capability hosts - in Foundry Standard mode
targetScope = 'resourceGroup'

param location string = resourceGroup().location

var resourceToken = toLower(uniqueString(resourceGroup().id, location))


// vnet doesn't have to be in the same RG as the AI Services
// each agent needs it's own delegated subnet, which means we need as many subnets as agents
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
  name: 'foundry-shared'
  params: {
    managedIdentityId: '' // Use System Assigned Identity
    name: 'ai-foundry-${resourceToken}'
    location: location
    appInsightsName: logAnalytics.outputs.applicationInsightsName
    publicNetworkAccess: 'Enabled'
    agentSubnetId: vnet.outputs.agentSubnetId // Use the first agent subnet
    deployments: [
      {
        name: 'gpt-35-turbo'
        properties: {
          model: {
            format: 'OpenAI'
            name: 'gpt-35-turbo'
            version: '0125'
          }
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

output capability1HostUrl string = project1.outputs.capabilityHostUrl
output capability2HostUrl string = project2.outputs.capabilityHostUrl
output ai1ConnectionUrl string = project1.outputs.aiConnectionUrl
output ai2ConnectionUrl string = project2.outputs.aiConnectionUrl
output foundry1_connection_string string = project1.outputs.foundry_connection_string
output foundry2_connection_string string = project2.outputs.foundry_connection_string
