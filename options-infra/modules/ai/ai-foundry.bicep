param existing_CogServices_Name string = ''
param existing_CogServices_RG_Name string = ''
param name string = ''
param location string = resourceGroup().location
param tags object = {}
param agentSubnetId string = ''
param appInsightsName string = ''
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

param textEmbeddings array = []
param chatGpt_Standard object = {}
param chatGpt_Premium object = {}
param deployModels bool = true

// --------------------------------------------------------------------------------------------------------------
// Variables
// --------------------------------------------------------------------------------------------------------------
var resourceGroupName = resourceGroup().name
var useExistingService = !empty(existing_CogServices_Name)
var cognitiveServicesKeySecretName = 'cognitive-services-key'
var deployments = deployModels
  ? union(textEmbeddings, [
      {
        name: chatGpt_Standard.DeploymentName
        model: {
          format: 'OpenAI'
          name: chatGpt_Standard.ModelName
          version: chatGpt_Standard.ModelVersion
        }
        sku: chatGpt_Standard.?sku ?? {
          name: 'Standard'
          capacity: chatGpt_Standard.DeploymentCapacity
        }
      }
      {
        name: chatGpt_Premium.DeploymentName
        model: {
          format: 'OpenAI'
          name: chatGpt_Premium.ModelName
          version: chatGpt_Premium.ModelVersion
        }
        sku: chatGpt_Premium.?sku ?? {
          name: 'Standard'
          capacity: chatGpt_Premium.DeploymentCapacity
        }
      }
    ])
  : []
// --------------------------------------------------------------------------------------------------------------
// split managed identity resource ID to get the name
var identityParts = split(managedIdentityId, '/')
// get the name of the managed identity
var managedIdentityName = length(identityParts) > 0 ? identityParts[length(identityParts) - 1] : ''

resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-07-31-preview' existing = if (!empty(managedIdentityName)) {
  name: managedIdentityName
}

// --------------------------------------------------------------------------------------------------------------
resource existingAccount 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' existing = if (useExistingService) {
  scope: resourceGroup(existing_CogServices_RG_Name)
  name: existing_CogServices_Name
}

// --------------------------------------------------------------------------------------------------------------
// Foundry is always of type AIServices
resource account 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' = if (!useExistingService) {
  name: name
  location: location
  tags: tags
  kind: 'AIServices'
  identity: !empty(managedIdentityId)
    ? {
        type: 'UserAssigned'
        userAssignedIdentities: {
          '${managedIdentityId}': {}
        }
      }
    : {
        type: 'SystemAssigned'
      }
  properties: {
    // required to work in AI Foundry
    allowProjectManagement: true
    publicNetworkAccess: publicNetworkAccess
    networkAcls: {
      bypass: 'AzureServices'

      defaultAction: 'Allow'
      ipRules: empty(myIpAddress)
        ? []
        : [
            {
              value: myIpAddress
            }
          ]
      virtualNetworkRules: []
    }
    networkInjections: (!empty(agentSubnetId)
      ? [
          {
            scenario: 'agent'
            subnetArmId: agentSubnetId
            useMicrosoftManagedNetwork: false
          }
        ]
      : null)
    customSubDomainName: toLower('${(name)}')
  }
  sku: sku

  // Creates the Azure Foundry connection Application Insights
  resource connection 'connections@2025-04-01-preview' = if (!empty(appInsightsName)) {
    name: 'applicationInsights'
    properties: {
      category: 'AppInsights'
      //group: 'ServicesAndApps'  // read-only...
      target: appInsights.id
      authType: 'ApiKey'
      isSharedToAll: true
      //isDefault: true  // not valid property
      credentials: {
        key: appInsights.properties.InstrumentationKey
      }
      metadata: {
        ApiType: 'Azure'
        ResourceId: appInsights.id
      }
    }
  }
}

@batchSize(1)
resource deployment 'Microsoft.CognitiveServices/accounts/deployments@2025-04-01-preview' = [
  for deployment in deployments: if (!useExistingService && deployModels) {
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

resource appInsights 'Microsoft.Insights/components@2020-02-02' existing = if (!empty(appInsightsName)) {
  name: appInsightsName
  scope: resourceGroup()
}

// --------------------------------------------------------------------------------------------------------------
// Outputs
// --------------------------------------------------------------------------------------------------------------
output id string = useExistingService ? existingAccount.id : account.id
output name string = useExistingService ? existingAccount.name : account.name
output endpoint string = useExistingService ? existingAccount.properties.endpoint : account.properties.endpoint
output resourceGroupName string = useExistingService ? existing_CogServices_RG_Name : resourceGroupName
output cognitiveServicesKeySecretName string = cognitiveServicesKeySecretName

output textEmbeddings array = textEmbeddings
output chatGpt_Standard object = chatGpt_Standard

output accountPrincipalId string = empty(managedIdentityId)
  ? account.identity.principalId
  : identity.properties.principalId
