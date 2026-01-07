// This bicep files deploys one resource group with the following resources:
// 1. The AI Foundry dependencies, such as VNet and
//    private endpoints for AI Search, Azure Storage and Cosmos DB
// 2. The AI Foundry itself
// 3. Two AI Projects with the capability hosts - in Foundry Standard mode
targetScope = 'resourceGroup'

param location string = resourceGroup().location
param openAiApiBase string
param openAiResourceId string
param openAiLocation string = location
param existingFoundryName string?
param projectsCount int = 1

var valid_config = empty(openAiApiBase) || empty(openAiResourceId)
  ? fail('OPENAI_API_BASE and OPENAI_RESOURCE_ID environment variables must be set.')
  : true

var resourceToken = toLower(uniqueString(resourceGroup().id, location))
var openAiParts = split(openAiResourceId, '/')
var openAiName = last(openAiParts)
var openAiSubscriptionId = openAiParts[2]
var openAiResourceGroupName = openAiParts[4]

module foundry_identity '../modules/iam/identity.bicep' = {
  name: 'foundry-identity-deployment'
  params: {
    identityName: 'foundry-${resourceToken}-identity'
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

module keyVault '../modules/kv/key-vault.bicep' = {
  name: 'key-vault-deployment-for-foundry'
  params: {
    tags: {}
    location: location
    name: take('kv-foundry-${resourceToken}', 24)
    logAnalyticsWorkspaceId: logAnalytics.outputs.logAnalyticsWorkspaceId
    doRoleAssignments: true
    secrets: []

    publicAccessEnabled: false
    privateEndpointSubnetId: vnet.outputs.peSubnetId
    privateEndpointName: 'pe-kv-foundry-${resourceToken}'
    privateDnsZoneResourceId: ai_dependencies.outputs.DNSZones['privatelink.vaultcore.azure.net']!.resourceId
  }
}

var foundryName = existingFoundryName ?? 'ai-foundry-${resourceToken}'

module foundry '../modules/ai/ai-foundry.bicep' = if (empty(existingFoundryName)) {
  name: 'foundry-deployment-${resourceToken}'
  params: {
    managedIdentityId: foundry_identity.outputs.managedIdentityId
    name: foundryName
    location: location
    publicNetworkAccess: 'Enabled'
    agentSubnetId: vnet.outputs.agentSubnetId // Use the first agent subnet
    deployments: [] // no models
    keyVaultResourceId: keyVault.outputs.AZURE_RESOURCE_KEY_VAULT_ID
    keyVaultConnectionEnabled: true
    existing_Foundry_Name: existingFoundryName
  }
}

// This is required due to KeyVault issue resulting in Foundry deployment timeout
// https://portal.microsofticm.com/imp/v5/incidents/details/21000000774829/summary - AKV Detach Bug
// https://msdata.visualstudio.com/Vienna/_workitems/edit/4814146/
module fake_foundry '../modules/ai/ai-foundry-fake.bicep' = if (!empty(existingFoundryName)) {
  name: 'fake-foundry-deployment-${resourceToken}'
  params: {
    managedIdentityId: foundry_identity.outputs.managedIdentityId
    name: foundryName
    location: location
    publicNetworkAccess: 'Enabled'
    agentSubnetId: vnet.outputs.agentSubnetId // Use the first agent subnet
    deployments: [] // no models
    keyVaultResourceId: keyVault.outputs.AZURE_RESOURCE_KEY_VAULT_ID
    keyVaultConnectionEnabled: true
    existing_Foundry_Name: existingFoundryName
  }
}



module identities '../modules/iam/identity.bicep' = [
  for i in range(1, projectsCount): {
    name: 'ai-project-${i}-identity-${resourceToken}'
    params: {
      identityName: 'ai-project-${i}-identity-${resourceToken}'
      location: location
    }
  }
]

@batchSize(1)
module projects '../modules/ai/ai-project-with-caphost.bicep' = [
  for i in range(1, projectsCount): {
    name: 'ai-project-${i}-with-caphost-${resourceToken}'
    params: {
      foundryName: foundryName
      location: location
      projectId: i
      aiDependencies: ai_dependencies.outputs.aiDependencies
      existingAiResourceId: null
      managedIdentityId: identities[i - 1].outputs.managedIdentityId
      appInsightsId: logAnalytics.outputs.applicationInsightsId
    }
    dependsOn: [foundry ?? fake_foundry]
  }
]

module ai_gateway '../modules/apim/ai-gateway.bicep' = {
  name: 'ai-gateway-deployment-${resourceToken}'
  params: {
    location: location
    resourceToken: resourceToken
    aiFoundryName: foundryName
    logAnalyticsWorkspaceId: logAnalytics.outputs.logAnalyticsWorkspaceId
    appInsightsId: logAnalytics.outputs.applicationInsightsId
    appInsightsInstrumentationKey: logAnalytics.outputs.appInsightsInstrumentationKey
    staticModels: [
      {
        name: 'gpt-4.1-mini'
        properties: {
          model: {
            name: 'gpt-4.1-mini'
            version: '2025-01-01-preview'
            format: 'OpenAI'
          }
        }
      }
      {
        name: 'gpt-5-mini'
        properties: {
          model: {
            name: 'gpt-5-mini'
            version: '2025-04-01-preview'
            format: 'OpenAI'
          }
        }
      }
      {
        name: 'o3-mini'
        properties: {
          model: {
            name: 'o3-mini'
            version: '2025-01-01-preview'
            format: 'OpenAI'
          }
        }
      }
    ]
    aiServicesConfig: [
      {
        name: openAiName
        resourceId: openAiResourceId
        endpoint: openAiApiBase
        location: openAiLocation
      }
    ]
  }
  dependsOn: [foundry ?? fake_foundry]
}

module apim_role_assignment '../modules/iam/role-assignment-cognitiveServices.bicep' = {
  name: 'apim-role-assignment-deployment-${resourceToken}'
  scope: resourceGroup(openAiSubscriptionId, openAiResourceGroupName)
  params: {
    accountName: openAiName
    projectPrincipalId: ai_gateway.outputs.apimPrincipalId
    roleName: 'Cognitive Services User'
  }
}

output project_connection_strings string[] = [for i in range(1, projectsCount): projects[i - 1].outputs.aiConnectionUrl]
output project_names string[] = [for i in range(1, projectsCount): projects[i - 1].outputs.projectName]
output config_validation_result bool = valid_config
output FOUNDRY_NAME string = foundryName
