// creates ai foundry and project - all self contained no BYO resources
param location string = resourceGroup().location

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

module foundry './modules/ai/ai-foundry.bicep' = {
  name: 'foundry'
  params: {
    managedIdentityId: identity.outputs.managedIdentityId
    name: 'ai-foundry-${resourceToken}'
    location: location
    appInsightsName: logAnalytics.outputs.applicationInsightsName
    publicNetworkAccess: 'Enabled'
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


module aiProject './modules/ai/ai-project.bicep' = {
  name: 'ai-project'
  params: {
    foundry_name: foundry.outputs.name
    location: location
    project_name: 'ai-project1'
    project_description: 'AI Project with models on Foundry'
    display_name: 'AI Project with models on Foundry'
    managedIdentityId: identity.outputs.managedIdentityId
    usingFoundryAiConnection: true // Use the AI Foundry connection for the project
    createHubCapabilityHost: true
  }
}

// This module creates the capability host for the project and account
module addProjectCapabilityHost 'modules/ai/add-project-capability-host.bicep' = {
  name: 'capabilityHost-configuration-deployment'
  params: {
    accountName: foundry.outputs.name
    projectName: aiProject.outputs.project_name
    cosmosDBConnection: aiProject.outputs.cosmosDBConnection
    azureStorageConnection: aiProject.outputs.azureStorageConnection
    aiSearchConnection: aiProject.outputs.aiSearchConnection
    aiFoundryConnectionName: aiProject.outputs.aiFoundryConnectionName
  }
}

output capabilityHostUrl string = 'https://portal.azure.com/#/resource/${aiProject.outputs.project_id}/capabilityHosts/${addProjectCapabilityHost.outputs.capabilityHostName}/overview'
output aiConnectionUrl string = 'https://portal.azure.com/#/resource/${foundry.outputs.id}/connections/${aiProject.outputs.aiFoundryConnectionName}/overview'
output foundry_connection_string string = aiProject.outputs.projectConnectionString
