import { aiServiceConfigType } from 'v2/inference-api.bicep'
import { subscriptionType } from 'v2/apim.bicep'

param location string = resourceGroup().location
param tags object = {}
param logAnalyticsWorkspaceId string
param appInsightsInstrumentationKey string = ''
param appInsightsId string = ''
param inferenceAPIType string = 'AzureOpenAI'
param inferenceAPIPath string = 'inference' // Path to the inference API in the APIM service

@description('Configuration array for AI Services')
param aiServicesConfig aiServiceConfigType[] = []

@description('The suffix to append to the API Management instance name. Defaults to a unique string based on subscription and resource group IDs.')
param resourceSuffix string = uniqueString(subscription().id, resourceGroup().id)

@description('The name of the subscriptions to be created in API Management for the AI Gateway')
param subscriptions subscriptionType[] = []

@allowed([
  'External'
  'Internal'
])
param virtualNetworkType string?
param subnetResourceId string?
@description('The pricing tier of this API Management service')
@allowed([
  'Consumption'
  'Developer'
  'Basic'
  'Basicv2'
  'Standard'
  'Standardv2'
  'Premium'
])
param apimSku string = 'Basicv2'
@allowed([
  'Enabled'
  'Disabled'
])
param publicNetworkAccess string = 'Enabled'

module apim 'v2/apim.bicep' = {
  name: 'apim-v2'
  params: {
    location: location
    tags: tags
    apimSubscriptionsConfig: subscriptions
    lawId: logAnalyticsWorkspaceId
    appInsightsInstrumentationKey: appInsightsInstrumentationKey
    appInsightsId: appInsightsId
    resourceSuffix: resourceSuffix
    apimSku: apimSku
    virtualNetworkType: virtualNetworkType
    subnetResourceId: subnetResourceId
    publicNetworkAccess: publicNetworkAccess
  }
}

var updatedInferencePolicyXml = replace(
  loadTextContent('policy.xml'),
  '{retry-count}',
  string(max(length(aiServicesConfig) - 1, 1)) // Ensure at least 1 retry
) // Try all backends

module inference_api 'v2/inference-api.bicep' = {
  name: 'inference-api-deployment'
  params: {
    policyXml: updatedInferencePolicyXml
    apiManagementName: apim.outputs.name
    apimLoggerId: apim.outputs.loggerId
    aiServicesConfig: aiServicesConfig
    inferenceAPIType: inferenceAPIType
    inferenceAPIPath: inferenceAPIPath
    configureCircuitBreaker: true
    resourceSuffix: resourceSuffix
    enableModelDiscovery: true
    appInsightsInstrumentationKey: appInsightsInstrumentationKey
    appInsightsId: appInsightsId
  }
}

output apimResourceId string = apim.outputs.id
output apimName string = apim.outputs.name
output inferenceApiId string = inference_api.outputs.apiId
output inferenceApiName string = inference_api.outputs.apiName
output subscriptions array = apim.outputs.apimSubscriptions
output apimPrincipalId string = apim.outputs.principalId
output apimPrivateIp string = apim.outputs.apimPrivateIp
output apimPublicIp string = apim.outputs.apimPublicIp
output apiUrl string = '${apim.outputs.gatewayUrl}/${inference_api.outputs.apiPath}'
