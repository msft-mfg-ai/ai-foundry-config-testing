param tags object = {}
param vnetResourceId string
@description('The location of the regional resources - ACA and Redis.')
param location string

var vnetLinks = empty(vnetResourceId) ? [] : [
  {
    virtualNetworkResourceId: vnetResourceId
  }
]

module kvDnsZone 'br/public:avm/res/network/private-dns-zone:0.8.0' = {
  name: 'keyvault-privateDnsZoneDeployment'
  params: {
    tags: tags
    // Required parameters
    name: 'privatelink.vaultcore.azure.net'
    // Non-required parameters
    location: 'global'
    virtualNetworkLinks: vnetLinks
  }
}

module acrDnsZone 'br/public:avm/res/network/private-dns-zone:0.8.0' = {
  name: 'acr-privateDnsZoneDeployment'
  params: {
    tags: tags
    // Required parameters
    name: 'privatelink.azurecr.io'
    // Non-required parameters
    location: 'global'
    virtualNetworkLinks: vnetLinks
  }
}

module cosmosDnsZone 'br/public:avm/res/network/private-dns-zone:0.8.0' = {
  name: 'cosmos-privateDnsZoneDeployment'
  params: {
    tags: tags
    // Required parameters
    name: 'privatelink.documents.azure.com'
    // Non-required parameters
    location: 'global'
    virtualNetworkLinks: vnetLinks
  }
}

module storageBlobDnsZone 'br/public:avm/res/network/private-dns-zone:0.8.0' = {
  name: 'storageBlob-privateDnsZoneDeployment'
  params: {
    tags: tags
    // Required parameters
    name: 'privatelink.blob.${environment().suffixes.storage}'
    // Non-required parameters
    location: 'global'
    virtualNetworkLinks: vnetLinks
  }
}

module storageQueueDnsZone 'br/public:avm/res/network/private-dns-zone:0.8.0' = {
  name: 'storageQueue-privateDnsZoneDeployment'
  params: {
    tags: tags
    // Required parameters
    name: 'privatelink.queue.${environment().suffixes.storage}'
    // Non-required parameters
    location: 'global'
    virtualNetworkLinks: vnetLinks
  }
}

module storageTableDnsZone 'br/public:avm/res/network/private-dns-zone:0.8.0' = {
  name: 'storageTable-privateDnsZoneDeployment'
  params: {
    tags: tags
    // Required parameters
    name: 'privatelink.table.${environment().suffixes.storage}'
    // Non-required parameters
    location: 'global'
    virtualNetworkLinks: vnetLinks
  }
}

module storageFileDnsZone 'br/public:avm/res/network/private-dns-zone:0.8.0' = {
  name: 'storageFile-privateDnsZoneDeployment'
  params: {
    tags: tags
    // Required parameters
    name: 'privatelink.file.${environment().suffixes.storage}'
    // Non-required parameters
    location: 'global'
    virtualNetworkLinks: vnetLinks
  }
}

module containerAppsDnsZone 'br/public:avm/res/network/private-dns-zone:0.8.0' = {
  name: 'containerApps-privateDnsZoneDeployment'
  params: {
    tags: tags
    // Required parameters
    name: 'privatelink.${location}.azurecontainerapps.io'
    // Non-required parameters
    location: 'global'
    virtualNetworkLinks: vnetLinks
  }
}

module redisDnsZone 'br/public:avm/res/network/private-dns-zone:0.8.0' = {
  name: 'redis-privateDnsZoneDeployment'
  params: {
    tags: tags
    // Required parameters
    name: 'privatelink.${location}.redis.azure.net'
    // Non-required parameters
    location: 'global'
    virtualNetworkLinks: vnetLinks
  }
}

module amlDnsZone 'br/public:avm/res/network/private-dns-zone:0.8.0' = {
  name: 'aml-privateDnsZoneDeployment'
  params: {
    tags: tags
    // Required parameters
    name: 'privatelink.api.azureml.ms'
    // Non-required parameters
    location: 'global'
    virtualNetworkLinks: vnetLinks
  }
}

module notebooksDnsZone 'br/public:avm/res/network/private-dns-zone:0.8.0' = {
  name: 'notebooks-privateDnsZoneDeployment'
  params: {
    tags: tags
    // Required parameters
    name: 'privatelink.notebooks.azure.net'
    // Non-required parameters
    location: 'global'
    virtualNetworkLinks: vnetLinks
  }
}

module aiServicesDnsZone 'br/public:avm/res/network/private-dns-zone:0.8.0' = {
  name: 'aiServices-privateDnsZoneDeployment'
  params: {
    tags: tags
    // Required parameters
    name: 'privatelink.services.ai.azure.com'
    // Non-required parameters
    location: 'global'
    virtualNetworkLinks: vnetLinks
  }
}

module openAiServicesDnsZone 'br/public:avm/res/network/private-dns-zone:0.8.0' = {
  name: 'openAiServices-privateDnsZoneDeployment'
  params: {
    tags: tags
    // Required parameters
    name: 'privatelink.openai.azure.com'
    // Non-required parameters
    location: 'global'
    virtualNetworkLinks: vnetLinks
  }
}

module cognitiveServicesDnsZone 'br/public:avm/res/network/private-dns-zone:0.8.0' = {
  name: 'cognitiveServices-privateDnsZoneDeployment'
  params: {
    tags: tags
    // Required parameters
    name: 'privatelink.cognitiveservices.azure.com'
    // Non-required parameters
    location: 'global'
    virtualNetworkLinks: vnetLinks
  }
}

@export()
type dnsZonesType = {
  keyVaultDnsZoneResourceId: string
  acrDnsZoneResourceId: string
  cosmosDnsZoneResourceId: string
  storageBlobDnsZoneResourceId: string
  storageQueueDnsZoneResourceId: string
  storageTableDnsZoneResourceId: string
  storageFileDnsZoneResourceId: string
  containerAppsDnsZoneResourceId: string
  redisDnsZoneResourceId: string
  amlWorkspaceDnsZoneResourceId: string
  notebooksDnsZoneResourceId: string
  aiServicesDnsZoneResourceId: string
  cognitiveServicesDnsZoneResourceId: string
  openAiDnsZoneResourceId: string
}

output dnsZonesOutput dnsZonesType = {
  keyVaultDnsZoneResourceId: kvDnsZone.outputs.resourceId
  acrDnsZoneResourceId: acrDnsZone.outputs.resourceId
  cosmosDnsZoneResourceId: cosmosDnsZone.outputs.resourceId
  storageBlobDnsZoneResourceId: storageBlobDnsZone.outputs.resourceId
  storageQueueDnsZoneResourceId: storageQueueDnsZone.outputs.resourceId
  storageTableDnsZoneResourceId: storageTableDnsZone.outputs.resourceId
  storageFileDnsZoneResourceId: storageFileDnsZone.outputs.resourceId
  containerAppsDnsZoneResourceId: containerAppsDnsZone.outputs.resourceId
  redisDnsZoneResourceId: redisDnsZone.outputs.resourceId
  amlWorkspaceDnsZoneResourceId: amlDnsZone.outputs.resourceId
  notebooksDnsZoneResourceId: notebooksDnsZone.outputs.resourceId
  aiServicesDnsZoneResourceId: aiServicesDnsZone.outputs.resourceId
  cognitiveServicesDnsZoneResourceId: cognitiveServicesDnsZone.outputs.resourceId
  openAiDnsZoneResourceId: openAiServicesDnsZone.outputs.resourceId
}
