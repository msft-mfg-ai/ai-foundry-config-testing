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
param subnetResourceId string
param peSubnetResourceId string

module apim 'apim.bicep' = {
  name: 'apim-deployment'
  params: {
    location: location
    logAnalyticsWorkspaceId: logAnalyticsWorkspaceId
    appInsightsInstrumentationKey: appInsightsInstrumentationKey
    appInsightsId: appInsightsId
    resourceSuffix: resourceToken
    aiServicesConfig: aiServicesConfig
    apimSku: 'Standardv2'
    virtualNetworkType: 'External'
    subnetResourceId: subnetResourceId
    // NotSupported: Blocking all public network access by setting property `publicNetworkAccess` of API Management service apim-xxxx is not enabled during service creation.
    publicNetworkAccess: null
  }
}

module apim_pe 'apim-pe.bicep' = {
  name: 'apim-pe-deployment'
  params: {
    apimName: apim.outputs.apimName
    peSubnetResourceId: peSubnetResourceId
  }
}

module apim_update 'apim.bicep' = {
  name: 'apim-update-deployment'
  params: {
    location: location
    logAnalyticsWorkspaceId: logAnalyticsWorkspaceId
    appInsightsInstrumentationKey: appInsightsInstrumentationKey
    appInsightsId: appInsightsId
    resourceSuffix: resourceToken
    aiServicesConfig: aiServicesConfig
    apimSku: 'Standardv2'
    virtualNetworkType: 'External'
    subnetResourceId: subnetResourceId
    // NotSupported: Blocking all public network access by setting property `publicNetworkAccess` of API Management service apim-xxxx is not enabled during service creation.
    // Need to run this weird update step after PE is attached.
    publicNetworkAccess: 'Disabled'
  }
  dependsOn: [apim_pe]
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
