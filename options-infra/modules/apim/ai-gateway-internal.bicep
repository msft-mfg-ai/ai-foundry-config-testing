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

var subnetIdParts = split(subnetResourceId, '/')
var subnetName = last(subnetIdParts)
var vnetResourceId = substring(subnetResourceId, 0, length(subnetResourceId) - length('/subnets/${subnetName}'))

module apim 'apim.bicep' = {
  name: 'apim-deployment'
  params: {
    location: location
    logAnalyticsWorkspaceId: logAnalyticsWorkspaceId
    appInsightsInstrumentationKey: appInsightsInstrumentationKey
    appInsightsId: appInsightsId
    resourceSuffix: resourceToken
    aiServicesConfig: aiServicesConfig
    apimSku: 'Developer'
    virtualNetworkType: 'Internal'
    subnetResourceId: subnetResourceId
  }
}

module apim_dns 'apim-dns.bicep' = {
  name: 'apim-dns-configuration'
  params: {
    apimIpAddress: apim.outputs.apimPrivateIp
    vnetResourceId: vnetResourceId
    apimName: apim.outputs.apimName
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
  }
}

output apimResourceId string = apim.outputs.apimResourceId
output apimName string = apim.outputs.apimName
output apimPrincipalId string = apim.outputs.apimPrincipalId
