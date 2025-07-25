param name string = ''
param location string = resourceGroup().location
param tags object = {}


param publicNetworkAccess string = ''
param sku object = {
  name: 'S0'
}
@description('Provide the IP address to allow access to the Azure Container Registry')
param myIpAddress string = ''
param managedIdentityId string

param deployments array = []


// --------------------------------------------------------------------------------------------------------------
// Variables
// --------------------------------------------------------------------------------------------------------------
var resourceGroupName = resourceGroup().name
var cognitiveServicesKeySecretName = 'oai-services-key'


// --------------------------------------------------------------------------------------------------------------
resource account 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' = {
  name: name
  location: location
  tags: tags
  kind: 'OpenAI'

  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentityId}': {}
    }
  }
  properties: {
    // required to work in AI Foundry
    publicNetworkAccess: publicNetworkAccess
    networkAcls: {
      bypass: 'AzureServices'

      defaultAction: empty(myIpAddress) ? 'Allow' : 'Deny'
      ipRules: empty(myIpAddress)
        ? []
        : [
            {
              value: myIpAddress
            }
          ]
    }
    customSubDomainName: toLower('${(name)}')
  }
  sku: sku
}

@batchSize(1)
resource deployment 'Microsoft.CognitiveServices/accounts/deployments@2025-04-01-preview' = [
  for deployment in deployments: {
    parent: account
    name: deployment.name
    properties: {
      model: deployment.model
      // // use the policy in the deployment if it exists, otherwise default to null
      // raiPolicyName: deployment.?raiPolicyName ?? null
    }
    // use the sku in the deployment if it exists, otherwise default to standard
    sku: deployment.?sku ?? { name: 'Standard', capacity: 20 }
  }
]

// --------------------------------------------------------------------------------------------------------------
// Outputs
// --------------------------------------------------------------------------------------------------------------
output id string = account.id
output name string = account.name
output endpoint string = account.properties.endpoint
output resourceGroupName string = resourceGroupName
output cognitiveServicesKeySecretName string = cognitiveServicesKeySecretName
output deployments array = deployments

