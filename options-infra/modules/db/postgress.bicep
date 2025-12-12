param name string
param location string = resourceGroup().location
param tags object = {}
param workspaceResourceId string
param privateEndpointSubnetId string
param privateDnsZoneResourceId string
param keyVaultName string
@allowed([
  'Standard_B1ms'
  'Standard_B1s'
  'Standard_B2ms'
  'Standard_B2s'
  'Standard_B4ms'
  'Standard_B8ms'
])
param skuName string = 'Standard_B1ms'

var pwdSecretName = toLower('${name}PGAdminPassword')
var password = uniqueString(resourceGroup().id, name, 'pgpassword')
var databaseConnectionString = 'postgresql://myPgAdmin:${password}@${flexibleServer.outputs.fqdn!}:5432/litellmdb'
var connectionStringSecretName = toLower('${name}PGConnectionString')

module keyvaultSecretPassword 'br/public:avm/res/key-vault/vault/secret:0.1.0' = {
  params: {
    keyVaultName: keyVaultName
    name: pwdSecretName
    value: password
  }
}

module keyvaultSecretConnectionString 'br/public:avm/res/key-vault/vault/secret:0.1.0' = {
  params: {
    keyVaultName: keyVaultName
    name: connectionStringSecretName
    value: databaseConnectionString
  }
}

module flexibleServer 'br/public:avm/res/db-for-postgre-sql/flexible-server:0.15.1' = {
  params: {
    // Required parameters
    availabilityZone: -1
    highAvailability: 'Disabled'
    highAvailabilityZone: -1
    name: name
    location: location
    skuName: skuName
    tier: 'Burstable'
    // Non-required parameters
    tags: tags
    administratorLogin: 'myPgAdmin'
    administratorLoginPassword: password
    authConfig: {
      activeDirectoryAuth: 'Disabled'
      passwordAuth: 'Enabled'
    }
    configurations: [
      // {
      //   name: 'log_min_messages'
      //   source: 'user-override'
      //   value: 'INFO'
      // }
      // {
      //   name: 'autovacuum_naptime'
      //   source: 'user-override'
      //   value: '80'
      // }
    ]
    databases: [
      {
        charset: 'UTF8'
        collation: 'en_US.utf8'
        name: 'litellmdb'
      }
    ]
    // delegatedSubnetResourceId: '<delegatedSubnetResourceId>'
    diagnosticSettings: [
      {
        metricCategories: [
          {
            category: 'AllMetrics'
          }
        ]
        name: 'customSetting'
        workspaceResourceId: workspaceResourceId
      }
    ]
    geoRedundantBackup: 'Disabled'
    privateEndpoints: [
      {
        name: 'pe-postgress-${name}'
        subnetResourceId: privateEndpointSubnetId
        tags: {}
        privateDnsZoneGroup: {
          privateDnsZoneGroupConfigs: [
            {
              privateDnsZoneResourceId: privateDnsZoneResourceId
            }
          ]
        }
      }
    ]
    roleAssignments: [
      // {
      //   principalId: '<principalId>'
      //   principalType: 'ServicePrincipal'
      //   roleDefinitionIdOrName: 'Owner'
      // }
      // {
      //   principalId: '<principalId>'
      //   principalType: 'ServicePrincipal'
      //   roleDefinitionIdOrName: 'b24988ac-6180-42a0-ab88-20f7382dd24c'
      // }
      // {
      //   principalId: '<principalId>'
      //   principalType: 'ServicePrincipal'
      //   roleDefinitionIdOrName: '<roleDefinitionIdOrName>'
      // }
    ]
  }
}

output pgAdminPwdSecretName string = pwdSecretName
output pgConnectionStringSecretName string = connectionStringSecretName
output fqdn string = flexibleServer.outputs.fqdn!
output postgressResourceId string = flexibleServer.outputs.resourceId!
