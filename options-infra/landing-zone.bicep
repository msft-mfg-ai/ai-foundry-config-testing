// template simulates a simple landing zone deployment with azure Open AI
param location string = resourceGroup().location

param resourceToken string = toLower(uniqueString(resourceGroup().id, location))
param aiServicesName string = 'foundry-landing-zone-${location}-${resourceToken}'

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
    name: aiServicesName
    location: location
    publicNetworkAccess: 'Disabled' // 'enabled' or 'disabled'
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

// vnet doesn't have to be in the same RG as the AI Services
// each agent needs it's own delegated subnet, which means we need as many subnets as agents
module vnet 'modules/networking/vnet.bicep' = {
  name: 'vnet'
  params: {
    vnetName: 'project-vnet-${resourceToken}'
    location: location
  }
}

module dnsZones './modules/networking/dns-zones.bicep' = {
  name: 'dns-zones'
  params: {
    vnetName: vnet.outputs.virtualNetworkName
    suffix: resourceToken
    vnetResourceGroupName: vnet.outputs.virtualNetworkResourceGroup
    vnetSubscriptionId: vnet.outputs.virtualNetworkSubscriptionId
  }
}

// TODO: is PE required when using trusted services?
// https://learn.microsoft.com/en-us/azure/ai-services/cognitive-services-virtual-networks?tabs=portal&WT.mc_id=Portal-Microsoft_Azure_ProjectOxford#grant-access-to-trusted-azure-services-for-azure-openai
// Microsoft.Search and Microsoft.CognitiveServices are supported by trusted services

module foundryPe 'modules/networking/private-endpoint.bicep' = {
  name: 'foundry-pe'
  params: {
    privateEndpointName: 'foundry-pe-${resourceToken}'
    location: location
    subnetId: vnet.outputs.peSubnetId
    targetResourceId: aiServices.outputs.id
    groupIds: [ 'account' ]
    zoneConfigs: [
      { name: '${aiServicesName}-dns-aiserv-config',  privateDnsZoneId: dnsZones.outputs.aiServicesPrivateDnsZoneId }
      { name: '${aiServicesName}-dns-openai-config',  privateDnsZoneId: dnsZones.outputs.openAiPrivateDnsZoneId } 
      { name: '${aiServicesName}-dns-cogserv-config', privateDnsZoneId: dnsZones.outputs.cognitiveServicesPrivateDnsZoneId } 
    ]
  }
}
