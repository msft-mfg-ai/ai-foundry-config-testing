@description('Name of Microsoft Foundry')
param foundryName string

@description('Name of the Foundry Project')
param projectName string

@description('Location for the deployment script. Should typically match resource group location.')
param location string = resourceGroup().location

@description('user-assigned managed identity resource id to run the deployment script.')
param scriptUserAssignedIdentityResourceId string

@description('Principal ID of the user-assigned managed identity to run the deployment script. Required if scriptUserAssignedIdentityResourceId is provided.')
param scriptUserAssignedIdentityPrincipalId string

param storageName string = 'script${uniqueString(resourceGroup().id, foundryName)}st'

var base_url = '${environment().resourceManager}subscriptions/${subscription().subscriptionId}/resourceGroups/${resourceGroup().name}/providers/Microsoft.CognitiveServices/accounts/${foundryName}/projects/${projectName}/capabilityHosts'

module storageAccount 'br/public:avm/res/storage/storage-account:0.30.0' = {
  name: 'storageAccount-${storageName}'
  params: {
    name: storageName
    location: location
    skuName: 'Standard_LRS'
    kind: 'StorageV2'
    tags: {
      SecurityControl: 'Ignore'
      'hidden-title': 'For deployment script'
    }
    allowSharedKeyAccess: true
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Allow'
    }
    roleAssignments: [
      {
        principalId: scriptUserAssignedIdentityPrincipalId
        principalType: 'ServicePrincipal'
        roleDefinitionIdOrName: 'Storage File Data Privileged Contributor'
      }
    ]
  }
}

module deploymentScript 'br/public:avm/res/resources/deployment-script:0.5.2' = {
  name: 'runScript-${uniqueString(foundryName, projectName)}'
  params: {
    // Required parameters
    kind: 'AzureCLI'
    name: 'runScriptScript-${uniqueString(foundryName, projectName)}'
    // Non-required parameters
    azCliVersion: '2.75.0'
    cleanupPreference: 'Always'
    location: location
    managedIdentities: {
      userAssignedResourceIds: [
        scriptUserAssignedIdentityResourceId
      ]
    }
    tags: {
      'hidden-title': 'For deployment script'
    }
    retentionInterval: 'PT1H'
    runOnce: true
    scriptContent: 'CAPHOST_NAME=$(az rest --method get --url "${base_url}?api-version=2025-06-01" --query "value[0].name" -o tsv) && az rest --method delete --url "${base_url}/$CAPHOST_NAME?api-version=2025-06-01 && sleep 30"'
    storageAccountResourceId: storageAccount.outputs.resourceId
    timeout: 'PT5M'
  }
}

