import { aiServiceConfigType } from 'v2/inference-api.bicep'
import { ModelType } from '../ai/connection-apim-gateway.bicep'

param location string = resourceGroup().location
param tags object = {}
param logAnalyticsWorkspaceResourceId string
param appInsightsInstrumentationKey string = ''
param appInsightsResourceId string = ''
param aiFoundryName string
param resourceToken string

param staticModels ModelType[] = []
param aiServicesConfig aiServiceConfigType[] = []

module apim 'apim.bicep' = {
  name: 'apim-deployment'
  params: {
    tags: tags
    location: location
    logAnalyticsWorkspaceId: logAnalyticsWorkspaceResourceId
    appInsightsInstrumentationKey: appInsightsInstrumentationKey
    appInsightsId: appInsightsResourceId
    resourceSuffix: resourceToken
    aiServicesConfig: aiServicesConfig
  }
}

module aiGatewayConnectionDynamic '../ai/connection-apim-gateway.bicep' = {
  name: 'apim-connection-dynamic'
  params: {
    aiFoundryName: aiFoundryName
    connectionName: 'apim-${resourceToken}-dynamic'
    apimResourceId: apim.outputs.apimResourceId
    apiName: apim.outputs.inferenceApiName
    apimSubscriptionName: apim.outputs.subscriptionName
    isSharedToAll: true
    listModelsEndpoint: '/deployments'
    getModelEndpoint: '/deployments/{deploymentName}'
    deploymentProvider: 'AzureOpenAI'
    inferenceAPIVersion: '2025-03-01-preview'
  }
}

module aiGatewayConnectionStatic '../ai/connection-apim-gateway.bicep' = if (!empty(staticModels)) {
  name: 'apim-connection-static'
  params: {
    aiFoundryName: aiFoundryName
    connectionName: 'apim-${resourceToken}-static'
    apimResourceId: apim.outputs.apimResourceId
    apiName: apim.outputs.inferenceApiName
    apimSubscriptionName: apim.outputs.subscriptionName
    isSharedToAll: true
    staticModels: staticModels
    inferenceAPIVersion: '2025-03-01-preview'
  }
}

module modelGatewayConnectionStatic '../ai/connection-modelgateway-static.bicep' = if (!empty(staticModels)) {
  name: 'model-gateway-connection-static'
  params: {
    aiFoundryName: aiFoundryName
    connectionName: 'model-gateway-${resourceToken}-static'
    apiKey: apim.outputs.subscriptionValue
    isSharedToAll: true
    gatewayName: 'apim'
    staticModels: staticModels
    inferenceAPIVersion: '2025-03-01-preview'
    targetUrl: apim.outputs.apiUrl
    deploymentInPath: 'true'
  }
}

module modelGatewayConnectionDynamic '../ai/connection-modelgateway-dynamic.bicep' = {
  name: 'model-gateway-connection-dynamic'
  params: {
    aiFoundryName: aiFoundryName
    connectionName: 'model-gateway-${resourceToken}-dynamic'
    apiKey: apim.outputs.subscriptionValue
    isSharedToAll: true
    gatewayName: 'apim'
    targetUrl: apim.outputs.apiUrl
    listModelsEndpoint: '/deployments'
    getModelEndpoint: '/deployments/{deploymentName}'
    deploymentProvider: 'AzureOpenAI'
    inferenceAPIVersion: '2025-03-01-preview'
    deploymentInPath: 'true'
  }
}

output apimResourceId string = apim.outputs.apimResourceId
output apimName string = apim.outputs.apimName
output apimPrincipalId string = apim.outputs.apimPrincipalId
