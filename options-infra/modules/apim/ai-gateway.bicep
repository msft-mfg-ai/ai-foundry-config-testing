import { aiServiceConfigType } from 'v2/inference-api.bicep'
import { ModelType } from '../ai/connection-apim-gateway.bicep'

param location string = resourceGroup().location
param logAnalyticsWorkspaceId string
param appInsightsInstrumentationKey string = ''
param appInsightsId string = ''
param aiFoundryName string
param resourceToken string

param staticModels ModelType[] = []
param aiServicesConfig aiServiceConfigType[] = []

module apim 'apim.bicep' = {
  name: 'apim-deployment'
  params: {
    location: location
    logAnalyticsWorkspaceId: logAnalyticsWorkspaceId
    appInsightsInstrumentationKey: appInsightsInstrumentationKey
    appInsightsId: appInsightsId
    resourceSuffix: resourceToken
    aiServicesConfig: aiServicesConfig
  }
}

module aiGatewayConnectionDynamic '../ai/connection-apim-gateway.bicep' = {
  name: 'ai-gateway-connection-dynamic'
  params: {
    aiFoundryName: aiFoundryName
    connectionName: 'aigateway-${resourceToken}-dynamic'
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
  name: 'ai-gateway-connection-static'
  params: {
    aiFoundryName: aiFoundryName
    connectionName: 'aigateway-${resourceToken}-static'
    apimResourceId: apim.outputs.apimResourceId
    apiName: apim.outputs.inferenceApiName
    apimSubscriptionName: apim.outputs.subscriptionName
    isSharedToAll: true
    staticModels: staticModels
    inferenceAPIVersion: '2025-03-01-preview'
  }
}

output apimResourceId string = apim.outputs.apimResourceId
output apimName string = apim.outputs.apimName
output apimPrincipalId string = apim.outputs.apimPrincipalId
