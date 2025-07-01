param location string = resourceGroup().location
@description('The resource ID of the existing Ai resource - Azure Open AI, AI Services or AI Foundry.')
param existingAiResourceId string = ''
@description('The Kind of AI Service, can be "AzureOpenAI" or "AIServices". For AI Foundry use AI Services')
@allowed([
  'AzureOpenAI'
  'AIServices'
])
param existingAiResourceKind string = 'AzureOpenAI' // Can be 'AzureOpenAI' or 'AIServices'

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

module aiProject './modules/ai/ai-project.bicep' = if (!empty(existingAiResourceId)) {
  name: 'ai-project'
  params: {
    foundry_name: foundry.outputs.name
    location: location
    project_name: 'ai-project1'
    project_description: 'AI Project with existing AI resource ${existingAiResourceId}'
    display_name: 'AI Project with ${existingAiResourceKind}'
    managedIdentityId: identity.outputs.managedIdentityId
    existingAiResourceId: existingAiResourceId
    existingAiKind: existingAiResourceKind
  }
}

module aiProject2 './modules/ai/ai-project.bicep' = {
  name: 'ai-project2'
  params: {
    foundry_name: foundry.outputs.name
    location: location
    project_name: 'ai-project2'
    project_description: 'AI Project with existing Azure OpenAI'
    display_name: 'AI Project with Azure OpenAI'
    managedIdentityId: identity.outputs.managedIdentityId
    existingAiResourceId: oai.outputs.id
    existingAiKind: 'AzureOpenAI' // For AI Foundry use AI Services
  }
}

module aiProject3 './modules/ai/ai-project.bicep' = {
  name: 'ai-project3'
  params: {
    foundry_name: foundry.outputs.name
    location: location
    project_name: 'ai-project3'
    project_description: 'AI Project with existing AI Services'
    display_name: 'AI Project with Azure AI Services'
    managedIdentityId: identity.outputs.managedIdentityId
    existingAiResourceId: aiServices.outputs.id
    existingAiKind: 'AIServices'
  }
}
