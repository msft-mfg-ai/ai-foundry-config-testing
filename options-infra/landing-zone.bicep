// template simulates a simple landing zone deployment with azure Open AI
param location string = resourceGroup().location

var resourceToken = toLower(uniqueString(resourceGroup().id, location))

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
    name: 'ai-services-lz-${resourceToken}'
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
    name: 'oai-lz-${resourceToken}'
    location: location
    publicNetworkAccess: 'enabled'
    deployments: [
      {
        name: 'gpt-4o-mini'
        model: {
          format: 'OpenAI'
          name: 'gpt-4o-mini'
          version: '2024-07-18'
        }
      }
    ]
  }
}
