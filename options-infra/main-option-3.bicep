// This bicep files deploys two resource groups:
// 1. The main resource group for the AI Project and Foundry
// 2. The resource group for the AI Foundry dependencies, such as VNet and
//    private endpoints for AI Search, Azure Storage and Cosmos DB
// The AI Project is created in the main resource group, but it uses the dependencies
// from the second resource group and AI Foundry from a different subscription, included by existingAiResourceId
targetScope = 'subscription'

param location string
param applicationName string = 'my-app'
param app1Name string = '${applicationName}-1'
param app2Name string = '${applicationName}-2'
var app1ResourceGroupName = '${app1Name}-rg'
var app2ResourceGroupName = '${app2Name}-rg'
var foundryDependenciesResourceGroupName = '${applicationName}-foundry-dependencies-rg'

@description('The resource ID of the existing Ai resource - Azure Open AI, AI Services or AI Foundry.')
param existingAiResourceId string

@description('The Kind of AI Service, can be "AzureOpenAI" or "AIServices". For AI Foundry use AI Services. Its not recommended to use Azure OpenAI resource, since that only provided access to OpenAI models.')
@allowed([
  'AzureOpenAI'
  'AIServices'
])
param existingAiResourceKind string = 'AIServices' // Can be 'AzureOpenAI' or 'AIServices'

@description('The name of the project capability host to be created')
param projectCapHost string = 'caphostproj'

var resourceToken = toLower(uniqueString(subscription().subscriptionId, location))

resource app1ResourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: app1ResourceGroupName
  location: location
}
resource app2ResourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: app2ResourceGroupName
  location: location
}
resource foundryDependenciesResourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: foundryDependenciesResourceGroupName
  location: location
}



// vnet doesn't have to be in the same RG as the AI Services
// each agent needs it's own delegated subnet, which means we need as many subnets as agents
module vnet 'modules/networking/vnet.bicep' = {
  name: 'vnet'
  scope: foundryDependenciesResourceGroup
  params: {
    vnetName: 'project-vnet-${resourceToken}'
    location: location
    extraAgentSubnets: 2
  }
}


module ai_dependencies './modules/ai/ai-dependencies-with-dns.bicep' = {
  name: 'vnet-with-dependencies'
  scope: foundryDependenciesResourceGroup
  params: {
    peSubnetName: vnet.outputs.peSubnetName
    vnetResourceId: vnet.outputs.virtualNetworkId
    resourceToken: resourceToken
    aiServicesName: '' // create AI serviced PE later
    aiAccountNameResourceGroupName: ''
  }
}

module app1 'modules/app/app-rg.bicep' = {
  name: 'app-${app1Name}'
  scope: app1ResourceGroup
  params: {
    location: location
    appName: app1Name
    capabilityHostName: projectCapHost
    agentSubnetId: vnet.outputs.extraAgentSubnetIds[0] // Use the first agent subnet
    aiDependencies: ai_dependencies.outputs.aiDependencies
    existingAiResourceId: existingAiResourceId
    existingAiResourceKind: existingAiResourceKind
  }
}

module app2 'modules/app/app-rg.bicep' = {
  name: 'app-${app2Name}'
  scope: app2ResourceGroup
  params: {
    location: location
    appName: app2Name
    capabilityHostName: projectCapHost
    agentSubnetId: vnet.outputs.extraAgentSubnetIds[1] // Use the second agent subnet
    aiDependencies: ai_dependencies.outputs.aiDependencies
    existingAiResourceId: existingAiResourceId
    existingAiResourceKind: existingAiResourceKind
  }
}

module ai1_private_endpoint 'modules/networking/ai-pe-dns.bicep' = {
  name: '${app1Name}-ai-private-endpoint'
  scope: foundryDependenciesResourceGroup
  params: {
    aiAccountName: app1.outputs.aiAccountName
    aiAccountNameResourceGroup: app1ResourceGroup.name
    peSubnetId: vnet.outputs.peSubnetId
    resourceToken: resourceToken
    vnetId: vnet.outputs.virtualNetworkId
    existingDnsZones: ai_dependencies.outputs.DNSZones
  }
}

module ai2_private_endpoint 'modules/networking/ai-pe-dns.bicep' = {
  name: '${app2Name}-ai-private-endpoint'
  scope: foundryDependenciesResourceGroup
  params: {
    aiAccountName: app2.outputs.aiAccountName
    aiAccountNameResourceGroup: app2ResourceGroup.name
    peSubnetId: vnet.outputs.peSubnetId
    resourceToken: resourceToken
    vnetId: vnet.outputs.virtualNetworkId
    existingDnsZones: ai_dependencies.outputs.DNSZones
  }
}

output capability1HostUrl string = app1.outputs.capabilityHostUrl
output capability2HostUrl string = app2.outputs.capabilityHostUrl
output ai1ConnectionUrl string = app1.outputs.aiConnectionUrl
output ai2ConnectionUrl string = app2.outputs.aiConnectionUrl
