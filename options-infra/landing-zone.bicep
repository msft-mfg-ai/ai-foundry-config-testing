// template simulates a simple landing zone deployment with azure Open AI
// this would go to AI-Subscription and build services that can be shared with app-landing-zone
// Deployment creates 2 AI Services: one private and one public
param location string = resourceGroup().location

param resourceToken string = toLower(uniqueString(resourceGroup().id, location))
param aiServicesName string = 'foundry-landing-zone-${location}-${resourceToken}'
param aiServicesPublicName string = 'foundry-landing-zone-${location}-PUBLIC-${resourceToken}'

// Foundry doesn't support cross-subscription VNet injection or cross subscription resources, so we need to deploy it in the same subscription
var doesFoundrySupportsCrossSubscriptionVnet = false

module identity './modules/iam/identity.bicep' = {
  name: 'app-identity'
  params: {
    identityName: 'app-project-identity'
    location: location
  }
}

module logAnalytics './modules/monitor/loganalytics.bicep' = {
  name: 'log-analytics'
  params: {
    newLogAnalyticsName: 'log-analytics'
    newApplicationInsightsName: 'app-insights'
    location: location
  }
}

module aiServices './modules/ai/ai-foundry.bicep' = {
  name: 'ai-services'
  params: {
    managedIdentityId: identity.outputs.managedIdentityId
    name: aiServicesName
    location: location
    publicNetworkAccess: 'Disabled' // 'enabled' or 'disabled'
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

module aiServicesPublic './modules/ai/ai-foundry.bicep' = {
  name: 'ai-services-public'
  params: {
    managedIdentityId: identity.outputs.managedIdentityId
    name: aiServicesPublicName
    location: location
    publicNetworkAccess: 'Enabled' // 'enabled' or 'disabled'
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

module managedEnvironment 'modules/aca/container-app-environment.bicep' = {
  name: 'managed-environment'
  params: {
    location: location
    appInsightsConnectionString: logAnalytics.outputs.appInsightsConnectionString
    name: 'aca${resourceToken}'
    logAnalyticsWorkspaceResourceId: logAnalytics.outputs.logAnalyticsWorkspaceId
    storages: []
    publicNetworkAccess: 'Disabled'
    infrastructureSubnetId: null
  }
}

module appMcp './modules/aca/container-app.bicep' = {
  name: 'app-mcp'
  params: {
    location: location
    name: 'aca-mcp-${resourceToken}'
    workloadProfileName: managedEnvironment.outputs.AZURE_RESOURCE_CONTAINER_APPS_WORKLOAD_PROFILE_NAME
    applicationInsightsConnectionString: logAnalytics.outputs.appInsightsConnectionString
    definition: {
      settings: []
    }
    ingressTargetPort: 3001
    existingImage: 'ghcr.io/karpikpl/wttr-docker:main'
    userAssignedManagedIdentityClientId: identity.outputs.managedIdentityClientId
    userAssignedManagedIdentityResourceId: identity.outputs.managedIdentityId
    ingressExternal: true
    cpu: '0.25'
    memory: '0.5Gi'
    scaleMaxReplicas: 1
    scaleMinReplicas: 1
    containerAppsEnvironmentResourceId: managedEnvironment.outputs.AZURE_RESOURCE_CONTAINER_APPS_ENVIRONMENT_ID
    keyVaultName: null
    probes: [
      {
        type: 'Readiness'
        httpGet: {
          path: '/health'
          port: 3001
        }
      }
    ]
  }
}

module appOpenAPI './modules/aca/container-app.bicep' = {
  name: 'app-openapi'
  params: {
    location: location
    name: 'aca-openapi-${resourceToken}'
    workloadProfileName: managedEnvironment.outputs.AZURE_RESOURCE_CONTAINER_APPS_WORKLOAD_PROFILE_NAME
    applicationInsightsConnectionString: logAnalytics.outputs.appInsightsConnectionString
    definition: {
      settings: []
    }
    ingressTargetPort: 3000
    existingImage: 'ghcr.io/karpikpl/wttr-docker:main'
    userAssignedManagedIdentityClientId: identity.outputs.managedIdentityClientId
    userAssignedManagedIdentityResourceId: identity.outputs.managedIdentityId
    ingressExternal: true
    cpu: '0.25'
    memory: '0.5Gi'
    scaleMaxReplicas: 1
    scaleMinReplicas: 1
    containerAppsEnvironmentResourceId: managedEnvironment.outputs.AZURE_RESOURCE_CONTAINER_APPS_ENVIRONMENT_ID
    keyVaultName: null
    probes: [
      {
        type: 'Readiness'
        httpGet: {
          path: '/health'
          port: 3000
        }
      }
    ]
  }
}

// vnet doesn't have to be in the same RG as the AI Services
// each agent needs it's own delegated subnet, which means we need as many subnets as agents
module vnet 'modules/networking/vnet.bicep' = if (doesFoundrySupportsCrossSubscriptionVnet) {
  name: 'vnet'
  params: {
    vnetName: 'project-vnet-${resourceToken}'
    location: location
  }
}

module ai_dependencies 'modules/ai-dependencies/standard-dependent-resources.bicep' = if (doesFoundrySupportsCrossSubscriptionVnet) {
  params: {
    location: location
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

// Private Endpoint and DNS Configuration
// This module sets up private network access for all Azure services:
// 1. Creates private endpoints in the specified subnet
// 2. Sets up private DNS zones for each service
// 3. Links private DNS zones to the VNet for name resolution
// 4. Configures network policies to restrict access to private endpoints only
module privateEndpointAndDNS 'modules/networking/private-endpoint-and-dns.bicep' = if (doesFoundrySupportsCrossSubscriptionVnet) {
  name: 'private-endpoints-and-dns'
  params: {
    aiAccountName: aiServices.outputs.name // AI Services to secure
    aiSearchName: ai_dependencies.outputs.aiSearchName // AI Search to secure
    storageName: ai_dependencies.outputs.azureStorageName // Storage to secure
    cosmosDBName: ai_dependencies.outputs.cosmosDBName
    vnetName: vnet.outputs.virtualNetworkName // VNet containing subnets
    peSubnetName: vnet.outputs.peSubnetName // Subnet for private endpoints
    suffix: resourceToken // Unique identifier
    vnetResourceGroupName: vnet.outputs.virtualNetworkResourceGroup
    vnetSubscriptionId: vnet.outputs.virtualNetworkSubscriptionId // Subscription ID for the VNet
    cosmosDBSubscriptionId: ai_dependencies.outputs.cosmosDBSubscriptionId // Subscription ID for Cosmos DB
    cosmosDBResourceGroupName: ai_dependencies.outputs.cosmosDBResourceGroupName // Resource Group for Cosmos DB
    aiSearchSubscriptionId: ai_dependencies.outputs.aiSearchServiceSubscriptionId // Subscription ID for AI Search Service
    aiSearchResourceGroupName: ai_dependencies.outputs.aiSearchServiceResourceGroupName // Resource Group for AI Search Service
    storageAccountResourceGroupName: ai_dependencies.outputs.azureStorageResourceGroupName // Resource Group for Storage Account
    storageAccountSubscriptionId: ai_dependencies.outputs.azureStorageSubscriptionId // Subscription ID for Storage Account
  }
}
