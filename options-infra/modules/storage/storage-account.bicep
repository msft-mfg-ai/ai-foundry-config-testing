param name string
param location string = resourceGroup().location
param tags object = {}
param managedIdentityId string

@description('Storage Account type')
@allowed([
  'Premium_LRS'
  'Premium_ZRS'
  'Standard_GRS'
  'Standard_GZRS'
  'Standard_LRS'
  'Standard_RAGRS'
  'Standard_RAGZRS'
  'Standard_ZRS'
])
param storageAccountType string = 'Standard_LRS'

@description('Specifies the kind of account.')
@allowed([
  'BlobStorage'
  'BlockBlobStorage'
  'FileStorage'
  'Storage'
  'StorageV2'
])
param kind string = 'StorageV2'

@description('Allow or disallow public access to all blobs or containers in the storage account.')
@allowed([
  'Enabled'
  'Disabled'
])
param publicBlobAccess string = 'Disabled'

@description('Allow or disallow public network access to Storage Account.')
@allowed([
  'Enabled'
  'Disabled'
])
param publicNetworkAccess string = 'Enabled'

@description('Describes the IP address to allow access to the Storage Account')
param myIpAddress string = ''

@description('Enable hierarchical namespace for Azure Data Lake Storage Gen2')
param isHnsEnabled bool = false

@description('Enable SFTP support')
param isSftpEnabled bool = false

@description('Minimum TLS version to be permitted on requests to storage.')
@allowed([
  'TLS1_0'
  'TLS1_1'
  'TLS1_2'
])
param minimumTlsVersion string = 'TLS1_2'

// Variables
var storageAccountName = name
var containerNames = [
  'ai-foundry-files'
  'agent-uploads'
  'vector-store'
  'documents'
]

// Network access rules
var networkAcls = {
  bypass: 'AzureServices'
  defaultAction: empty(myIpAddress) ? 'Allow' : 'Deny'
  ipRules: empty(myIpAddress) ? [] : [
    {
      value: myIpAddress
      action: 'Allow'
    }
  ]
  virtualNetworkRules: []
}

// Storage Account
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: storageAccountType
  }
  kind: kind
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentityId}': {}
    }
  }
  properties: {
    dnsEndpointType: 'Standard'
    defaultToOAuthAuthentication: false
    publicNetworkAccess: publicNetworkAccess
    allowBlobPublicAccess: publicBlobAccess == 'Enabled'
    allowSharedKeyAccess: true
    allowCrossTenantReplication: false
    minimumTlsVersion: minimumTlsVersion
    allowedCopyScope: 'AAD'
    isHnsEnabled: isHnsEnabled
    isSftpEnabled: isSftpEnabled
    networkAcls: publicNetworkAccess == 'Enabled' ? networkAcls : null
    supportsHttpsTrafficOnly: true
    encryption: {
      requireInfrastructureEncryption: false
      services: {
        file: {
          keyType: 'Account'
          enabled: true
        }
        blob: {
          keyType: 'Account'
          enabled: true
        }
      }
      keySource: 'Microsoft.Storage'
    }
    accessTier: 'Hot'
  }
}

// Blob Service
resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    changeFeed: {
      enabled: false
    }
    restorePolicy: {
      enabled: false
    }
    containerDeleteRetentionPolicy: {
      enabled: true
      days: 7
    }
    cors: {
      corsRules: []
    }
    deleteRetentionPolicy: {
      allowPermanentDelete: false
      enabled: true
      days: 7
    }
    isVersioningEnabled: false
  }
}

// Containers for AI Foundry
resource containers 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = [for containerName in containerNames: {
  parent: blobService
  name: containerName
  properties: {
    immutableStorageWithVersioning: {
      enabled: false
    }
    defaultEncryptionScope: '$account-encryption-key'
    denyEncryptionScopeOverride: false
    publicAccess: 'None'
  }
}]

// File Service
resource fileService 'Microsoft.Storage/storageAccounts/fileServices@2023-05-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    protocolSettings: {
      smb: {
        versions: 'SMB2.1;SMB3.0;SMB3.1.1'
        authenticationMethods: 'NTLMv2;Kerberos'
        kerberosTicketEncryption: 'RC4-HMAC;AES-256'
        channelEncryption: 'AES-128-CCM;AES-128-GCM;AES-256-GCM'
      }
    }
    cors: {
      corsRules: []
    }
    shareDeleteRetentionPolicy: {
      enabled: true
      days: 7
    }
  }
}

// File Share for AI Foundry
resource fileShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2023-05-01' = {
  parent: fileService
  name: 'ai-foundry-share'
  properties: {
    accessTier: 'TransactionOptimized'
    shareQuota: 1024
    enabledProtocols: 'SMB'
  }
}

// Queue Service
resource queueService 'Microsoft.Storage/storageAccounts/queueServices@2023-05-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    cors: {
      corsRules: []
    }
  }
}

// Table Service
resource tableService 'Microsoft.Storage/storageAccounts/tableServices@2023-05-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    cors: {
      corsRules: []
    }
  }
}

// Outputs
output id string = storageAccount.id
output name string = storageAccount.name
output primaryEndpoints object = storageAccount.properties.primaryEndpoints
output primaryKey string = storageAccount.listKeys().keys[0].value
output secondaryKey string = storageAccount.listKeys().keys[1].value
output connectionString string = 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'
output containerNames array = containerNames
output fileShareName string = fileShare.name
