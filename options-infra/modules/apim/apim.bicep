import { aiServiceConfigType } from 'v2/inference-api.bicep'

param location string = resourceGroup().location
param logAnalyticsWorkspaceId string
param appInsightsInstrumentationKey string = ''
param appInsightsId string = ''
param inferenceAPIType string = 'AzureOpenAI'
param inferenceAPIPath string = 'inference' // Path to the inference API in the APIM service

@description('Configuration array for AI Services')
param aiServicesConfig aiServiceConfigType[] = []

@description('The suffix to append to the API Management instance name. Defaults to a unique string based on subscription and resource group IDs.')
param resourceSuffix string = uniqueString(subscription().id, resourceGroup().id)

param subscriptionName string = 'foundry-apim-subscription'
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

module apim 'v2/apim.bicep' = {
  name: 'apim-v2'
  params: {
    location: location
    apimSubscriptionsConfig: [
      { displayName: 'Foundry APIM Subscription', name: subscriptionName }
    ]
    lawId: logAnalyticsWorkspaceId
    appInsightsInstrumentationKey: appInsightsInstrumentationKey
    appInsightsId: appInsightsId
    resourceSuffix: resourceSuffix
    apimSku: apimSku
    virtualNetworkType: virtualNetworkType
    subnetResourceId: subnetResourceId
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

var apimSubscriptionLookup = filter(apim.outputs.apimSubscriptions, sub => sub.name == subscriptionName)

output apimResourceId string = apim.outputs.id
output apimName string = apim.outputs.name
output inferenceApiId string = inference_api.outputs.apiId
output inferenceApiName string = inference_api.outputs.apiName
output subscriptionName string = subscriptionName
output subscriptionValue string = empty(apimSubscriptionLookup) ? '' : first(apimSubscriptionLookup).key
output apimPrincipalId string = apim.outputs.principalId
output apimPrivateIp string = apim.outputs.apimPrivateIp
output apimPublicIp string = apim.outputs.apimPublicIp
output apiUrl string = '${apim.outputs.gatewayUrl}/${inference_api.outputs.apiPath}'
