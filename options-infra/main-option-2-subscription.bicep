// Subscription scope deployment - creates resource groups and deploys resources
targetScope = 'subscription'

// Parameters
@description('The location for all resources')
param location string = 'eastus'

@description('The name of the resource group to create')
param resourceGroupName string = 'rg-ai-foundry'

@description('The resource ID of the existing Azure OpenAI resource.')
param existingAoaiResourceId string = ''

@description('Optional tags to apply to all resources')
param tags object = {}

// Variables
var resourceToken = toLower(uniqueString(subscription().id, location))

// --------------------------------------------------------------------------------------------------------------
// -- Resource Group Creation --------------------------------------------------------------------------------
// --------------------------------------------------------------------------------------------------------------
resource resourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: resourceGroupName
  location: location
  tags: tags
}

// --------------------------------------------------------------------------------------------------------------
// -- Log Analytics Workspace and App Insights Module -------------------------------------------------------
// --------------------------------------------------------------------------------------------------------------
module logAnalytics './modules/monitor/loganalytics.bicep' = {
  name: 'law'
  scope: resourceGroup
  params: {
    newLogAnalyticsName: 'project-log-analytics-${resourceToken}'
    newApplicationInsightsName: 'project-app-insights-${resourceToken}'
    location: location
  }
}

// --------------------------------------------------------------------------------------------------------------
// -- Identity Module -----------------------------------------------------------------------------------------
// --------------------------------------------------------------------------------------------------------------
module identity './modules/iam/identity.bicep' = {
  name: 'app-identity'
  scope: resourceGroup
  params: {
    identityName: 'app-project-identity-${resourceToken}'
    location: location
  }
}

// --------------------------------------------------------------------------------------------------------------
// -- AI Services Module -------------------------------------------------------------------------------------
// --------------------------------------------------------------------------------------------------------------
module aiServices './modules/ai/ai-services.bicep' = {
  name: 'ai-services'
  scope: resourceGroup
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

// --------------------------------------------------------------------------------------------------------------
// -- Azure OpenAI Module ------------------------------------------------------------------------------------
// --------------------------------------------------------------------------------------------------------------
module oai './modules/ai/azure-oai.bicep' = {
  name: 'oai'
  scope: resourceGroup
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

// --------------------------------------------------------------------------------------------------------------
// -- AI Foundry Module --------------------------------------------------------------------------------------
// --------------------------------------------------------------------------------------------------------------
module foundry './modules/ai/ai-foundry.bicep' = {
  name: 'foundry'
  scope: resourceGroup
  params: {
    managedIdentityId: identity.outputs.managedIdentityId
    name: 'ai-foundry-${resourceToken}'
    location: location
    appInsightsName: logAnalytics.outputs.applicationInsightsName
    publicNetworkAccess: 'enabled'
    deployModels: false
  }
}

// --------------------------------------------------------------------------------------------------------------
// -- AI Project 1 Module ------------------------------------------------------------------------------------
// --------------------------------------------------------------------------------------------------------------
module aiProject './modules/ai/ai-project.bicep' = {
  name: 'ai-project'
  scope: resourceGroup
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

// --------------------------------------------------------------------------------------------------------------
// -- AI Project 2 Module ------------------------------------------------------------------------------------
// --------------------------------------------------------------------------------------------------------------
module aiProject2 './modules/ai/ai-project.bicep' = {
  name: 'ai-project2'
  scope: resourceGroup
  params: {
    foundry_name: foundry.outputs.name
    location: location
    project_name: 'ai-project2-${resourceToken}'
    project_description: 'AI Project 2 Description'
    display_name: 'AI Project 2 Display Name'
    managedIdentityId: identity.outputs.managedIdentityId
    existingAoaiResourceId: empty(existingAoaiResourceId) ? oai.outputs.id : existingAoaiResourceId
  }
}

// --------------------------------------------------------------------------------------------------------------
// -- Outputs -------------------------------------------------------------------------------------------------
// --------------------------------------------------------------------------------------------------------------
@description('The name of the created resource group')
output resourceGroupName string = resourceGroup.name

@description('The location of the deployed resources')
output location string = location

@description('The AI Foundry name')
output aiFoundryName string = foundry.outputs.name

@description('The AI Services endpoint')
output aiServicesEndpoint string = aiServices.outputs.endpoint

@description('The Azure OpenAI endpoint')
output azureOpenAIEndpoint string = oai.outputs.endpoint
