// This bicep files deploys one resource group with the following resources:
// 1. The AI Foundry dependencies, such as VNet and
//    private endpoints for AI Search, Azure Storage and Cosmos DB
// 2. The AI Foundry itself
// 3. Two AI Projects with the capability hosts - in Foundry Standard mode
targetScope = 'resourceGroup'

param location string = resourceGroup().location
@secure()
param openAiApiKey string
param openAiApiBase string

var valid_config = empty(openAiApiKey) || empty(openAiApiBase)
  ? fail('Both OPENAI_API_KEY and OPENAI_API_BASE environment variables must be set.')
  : true

var resourceToken = toLower(uniqueString(resourceGroup().id, location))

module identity '../modules/iam/identity.bicep' = {
  name: 'project-identity'
  params: {
    identityName: 'app-${resourceToken}-project-identity'
    location: location
  }
}

// vnet doesn't have to be in the same RG as the AI Services
// each foundry needs it's own delegated subnet, projects inside of one Foundry share the subnet for the Agents Service
module vnet '../modules/networking/vnet.bicep' = {
  name: 'vnet'
  params: {
    vnetName: 'project-vnet-${resourceToken}'
    location: location
    extraAgentSubnets: 1
  }
}

module ai_dependencies '../modules/ai/ai-dependencies-with-dns.bicep' = {
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
module logAnalytics '../modules/monitor/loganalytics.bicep' = {
  name: 'log-analytics'
  params: {
    newLogAnalyticsName: 'log-analytics'
    newApplicationInsightsName: 'app-insights'
    location: location
  }
}

module foundry '../modules/ai/ai-foundry.bicep' = {
  name: 'foundry-deployment-${resourceToken}'
  params: {
    managedIdentityId: '' // Use System Assigned Identity
    name: 'ai-foundry-${resourceToken}'
    location: location
    appInsightsId: logAnalytics.outputs.applicationInsightsId
    publicNetworkAccess: 'Enabled'
    agentSubnetId: vnet.outputs.agentSubnetId // Use the first agent subnet
    deployments: [] // no models
  }
}

module identities '../modules/iam/identity.bicep' = [
  for i in range(1, 3): {
    name: 'ai-project-${i}-identity-${resourceToken}'
    params: {
      identityName: 'ai-project-${i}-identity-${resourceToken}'
      location: location
    }
  }
]

@batchSize(1)
module projects '../modules/ai/ai-project-with-caphost.bicep' = [
  for i in range(1, 3): {
    name: 'ai-project-${i}-with-caphost-${resourceToken}'
    params: {
      foundryName: foundry.outputs.name
      location: location
      projectId: i
      aiDependencies: ai_dependencies.outputs.aiDependencies
      existingAiResourceId: null
      managedIdentityId: identities[i - 1].outputs.managedIdentityId
    }
  }
]

module project4 '../modules/ai/ai-project-with-caphost.bicep' = {
  name: 'ai-project-4-with-caphost-${resourceToken}'
  params: {
    foundryName: foundry.outputs.name
    location: location
    projectId: 4
    aiDependencies: ai_dependencies.outputs.aiDependencies
    existingAiResourceId: null
    managedIdentityId: null
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

module dnsPostgress 'br/public:avm/res/network/private-dns-zone:0.7.1' = {
  name: 'dns-postgress'
  params: {
    name: 'privatelink.postgres.database.azure.com'
    virtualNetworkLinks: [
      {
        virtualNetworkResourceId: vnet.outputs.virtualNetworkId
      }
    ]
  }
}

module liteLlm '../modules/litellm/lite-llm.bicep' = {
  name: 'lite-llm-deployment-${resourceToken}'
  params: {
    location: location
    resourceToken: resourceToken
    identityResourceId: identity.outputs.managedIdentityId
    logAnalyticsWorkspaceResourceId: logAnalytics.outputs.logAnalyticsWorkspaceId
    appInsightsConnectionString: logAnalytics.outputs.appInsightsConnectionString
    virtualNetworkResourceId: vnet.outputs.virtualNetworkId
    privateEndpointSubnetId: vnet.outputs.peSubnetId
    acaSubnetResourceId: vnet.outputs.extraAgentSubnetIds[0]
    keyVaultDnsZoneResourceId: ai_dependencies.outputs.DNSZones['privatelink.vaultcore.azure.net']!.resourceId
    postgressDnsZoneResourceId: dnsPostgress.outputs.resourceId
    openAiApiKey: openAiApiKey
    openAiApiBase: openAiApiBase
    aiFoundryName: foundry.outputs.name
    litlLlmPublicFqdn: 'http://${publicIpAddress.outputs.ipAddress}'
    liteLlmConfigYaml: '''
model_list:
  - model_name: azure-gpt-4.1-mini
    litellm_params:
      model: azure/gpt-4.1-mini
      api_base: os.environ/AZURE_API_BASE # runs os.getenv("AZURE_API_BASE")
      api_key: os.environ/AZURE_API_KEY # runs os.getenv("AZURE_API_KEY")
      api_version: "2025-01-01-preview"
  - model_name: azure-gpt-5-mini
    litellm_params:
      model: azure/gpt-5-mini
      api_base: os.environ/AZURE_API_BASE # runs os.getenv("AZURE_API_BASE")
      api_key: os.environ/AZURE_API_KEY # runs os.getenv("AZURE_API_KEY")
      api_version: "2025-04-01-preview"
  - model_name: azure-o3-mini
    litellm_params:
      model: azure/o3-mini
      api_base: os.environ/AZURE_API_BASE # runs os.getenv("AZURE_API_BASE")
      api_key: os.environ/AZURE_API_KEY # runs os.getenv("AZURE_API_KEY")
      api_version: "2025-01-01-preview"            
    '''
    // litellm_settings:
    //     enable_azure_ad_token_refresh: true
    // https://docs.litellm.ai/docs/providers/azure#azure-ad-token-refresh---defaultazurecredential
  }
}

module publicIpAddress 'br/public:avm/res/network/public-ip-address:0.9.1' = {
  params: {
    // Required parameters
    name: 'app-gateway-${resourceToken}-public-ip'
    // Non-required parameters
    location: location
    availabilityZones: []
  }
}

module acaAppGateway '../modules/appgtw/application-gateway.bicep' = {
  name: 'aca-app-gateway-deployment-${resourceToken}'
  params: {
    location: location
    name: 'app-gateway-${resourceToken}'
    applicationFqdn: liteLlm.outputs.liteLlmAcaFqdn
    applicationGatewaySubnetId: vnet.outputs.appGwSubnetId
    acaName: 'aca${resourceToken}'
    publicIpResourceId: publicIpAddress.outputs.resourceId
  }
}

output project_connection_strings string[] = [for i in range(1, 3): projects[i - 1].outputs.aiConnectionUrl]
output project_names string[] = [for i in range(1, 3): projects[i - 1].outputs.projectName]
output config_validation_result bool = valid_config
