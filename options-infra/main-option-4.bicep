param location string = resourceGroup().location
@description('The resource ID of the existing Azure OpenAI resource.')
param existingAoaiResourceId string = ''

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

module aiProject './modules/ai/ai-project.bicep' = {
  name: 'ai-project'
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
