@description('Name of the Vnet')
param vnetName string
@description('Suffix for unique resource names')
param suffix string

@description('Resource Group name for existing Virtual Network (if different from current resource group)')
param vnetResourceGroupName string = resourceGroup().name

@description('Subscription ID for Virtual Network')
param vnetSubscriptionId string = subscription().subscriptionId

/* -------------------------------------------- Private DNS Zones -------------------------------------------- */

// Format: 1) Private DNS Zone
//         2) Link Private DNS Zone to VNet
//         3) Create DNS Zone Group for Private Endpoint

// Private DNS Zone for AI Services (Account)
// 1) Enables custom DNS resolution for AI Services private endpoint

var aiServicesDnsZoneName = 'privatelink.services.ai.azure.com'
var openAiDnsZoneName = 'privatelink.openai.azure.com'
var cognitiveServicesDnsZoneName = 'privatelink.cognitiveservices.azure.com'
var aiSearchDnsZoneName = 'privatelink.search.windows.net'
var storageDnsZoneName = 'privatelink.blob.${environment().suffixes.storage}'
var cosmosDBDnsZoneName = 'privatelink.documents.azure.com'

// Reference existing network resources
resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' existing = {
  name: vnetName
  scope: resourceGroup(vnetSubscriptionId, vnetResourceGroupName)
}


// ---- DNS Zone Resources and References ----
resource aiServicesPrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: aiServicesDnsZoneName
  location: 'global'
}


resource openAiPrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: openAiDnsZoneName
  location: 'global'
}

resource cognitiveServicesPrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: cognitiveServicesDnsZoneName
  location: 'global'
}


resource aiSearchPrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' =  {
  name: aiSearchDnsZoneName
  location: 'global'
}

resource storagePrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' =  {
  name: storageDnsZoneName
  location: 'global'
}


resource cosmosDBPrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: cosmosDBDnsZoneName
  location: 'global'
}

// ---- DNS VNet Links ----
resource aiServicesLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' =  {
  parent: aiServicesPrivateDnsZone
  location: 'global'
  name: 'aiServices-${suffix}-link'
  properties: {
    virtualNetwork: { id: vnet.id }
    registrationEnabled: false
  }
}
resource openAiLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' =  {
  parent: openAiPrivateDnsZone
  location: 'global'
  name: 'aiServicesOpenAI-${suffix}-link'
  properties: {
    virtualNetwork: { id: vnet.id }
    registrationEnabled: false
  }
}
resource cognitiveServicesLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' =  {
  parent: cognitiveServicesPrivateDnsZone
  location: 'global'
  name: 'aiServicesCognitiveServices-${suffix}-link'
  properties: {
    virtualNetwork: { id: vnet.id }
    registrationEnabled: false
  }
}
resource aiSearchLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' =  {
  parent: aiSearchPrivateDnsZone
  location: 'global'
  name: 'aiSearch-${suffix}-link'
  properties: {
    virtualNetwork: { id: vnet.id }
    registrationEnabled: false
  }
}
resource storageLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' =  {
  parent: storagePrivateDnsZone
  location: 'global'
  name: 'storage-${suffix}-link'
  properties: {
    virtualNetwork: { id: vnet.id }
    registrationEnabled: false
  }
}
resource cosmosDBLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' =  {
  parent: cosmosDBPrivateDnsZone
  location: 'global'
  name: 'cosmosDB-${suffix}-link'
  properties: {
    virtualNetwork: { id: vnet.id }
    registrationEnabled: false
  }
}

output aiServicesPrivateDnsZoneId string = aiServicesPrivateDnsZone.id
output openAiPrivateDnsZoneId string = openAiPrivateDnsZone.id
output cognitiveServicesPrivateDnsZoneId string = cognitiveServicesPrivateDnsZone.id
output aiSearchPrivateDnsZoneId string = aiSearchPrivateDnsZone.id
output storagePrivateDnsZoneId string = storagePrivateDnsZone.id
output cosmosDBPrivateDnsZoneId string = cosmosDBPrivateDnsZone.id
