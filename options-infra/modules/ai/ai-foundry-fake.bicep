param existing_Foundry_Name string = ''
param existing_Foundry_RG_Name string = resourceGroup().name
param existing_Foundry_SubId string = subscription().subscriptionId
param name string = ''
param location string = resourceGroup().location
param tags object = {}
param agentSubnetId string = ''
@allowed([
  'Disabled'
  'Enabled'
])
param publicNetworkAccess string = 'Enabled'
param sku object = {
  name: 'S0'
}
@description('Provide the IP address to allow access to the Azure Container Registry')
param myIpAddress string = ''
param managedIdentityId string = ''

// Keyvault integration
param keyVaultResourceId string?
@description('Bunch of known issues with KeyVault integration, so disable by default')
param keyVaultConnectionEnabled bool = false

// --------------------------------------------------------------------------------------------------------------
// Variables
// --------------------------------------------------------------------------------------------------------------
var useExistingService = !empty(existing_Foundry_Name)
var cognitiveServicesKeySecretName = 'cognitive-services-key'
param gpt41Deployment aiModelTDeploymentType?
param deployments aiModelTDeploymentType[] = []

@export()
type aiModelTDeploymentType = {
  @description('The name of the deployment')
  name: string
  properties: {
    model: {
      @description('The name of the model - often the same as the deployment name')
      name: string
      @description('The version of the model, e.g. "2024-11-20" or "0125"')
      version: string
      format: 'OpenAI'
    }
  }
  sku: {
    name: 'Standard' | 'GlobalStandard'
    capacity: int
  }?
}

// --------------------------------------------------------------------------------------------------------------
// split managed identity resource ID to get the name
var identityParts = split(managedIdentityId, '/')
// get the name of the managed identity
var managedIdentityName = length(identityParts) > 0 ? identityParts[length(identityParts) - 1] : ''

resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-07-31-preview' existing = {
  name: managedIdentityName
}

// --------------------------------------------------------------------------------------------------------------
// Outputs
// --------------------------------------------------------------------------------------------------------------
output id string = '/subscriptions/${existing_Foundry_SubId}/resourceGroups/${existing_Foundry_RG_Name}/providers/Microsoft.CognitiveServices/accounts/${existing_Foundry_Name}'
@description('The name of Foundry Account')
output name string = existing_Foundry_Name
output endpoint string = 'https://${existing_Foundry_Name}.services.ai.azure.com/'
output resourceGroupName string = existing_Foundry_RG_Name
output subscriptionId string =existing_Foundry_SubId
output cognitiveServicesKeySecretName string = cognitiveServicesKeySecretName

output accountPrincipalId string = identity.properties.principalId
output is_fake_foundry_valid bool = empty(existing_Foundry_Name) || empty(managedIdentityId) ? fail('For fake Foundry, both existing_Foundry_Name and managedIdentityId must be provided') : true
