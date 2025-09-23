// This bicep files deploys Azure Machine learning
// ------------------

targetScope = 'resourceGroup'

param location string = resourceGroup().location

var resourceToken = toLower(uniqueString(resourceGroup().id, location))

module identity 'modules/aml/user-assigned-managed-identity.bicep' = {
  name: 'aml-identity-deployment'
  params: {
    location: location
    name: 'aml-identity-${resourceToken}'
  }
}

module roleAssignments 'modules/aml/role-assignment.bicep' = {
  name: 'aml-role-assignments-deployment'
  params: {
    principalId: identity.outputs.AZURE_RESOURCE_USER_ASSIGNED_IDENTITY_PRINCIPAL_ID
  }
}

// https://github.com/Azure/bicep-registry-modules/blob/main/avm/ptn/ai-ml/ai-foundry/README.md
module aiFoundry 'br/public:avm/ptn/ai-ml/ai-foundry:0.4.0' = {
  name: 'aiFoundryDeployment'
  params: {
    // Required parameters
    baseName: take('foundry-${resourceToken}',12)
    // Non-required parameters
    aiModelDeployments: [
      {
        model: {
          format: 'OpenAI'
          name: 'gpt-4o'
          version: '2024-11-20'
        }
        name: 'gpt-4o'
        sku: {
          capacity: 1
          name: 'Standard'
        }
      }
    ]
    aiFoundryConfiguration: {
      disableLocalAuth: true
      roleAssignments: [
        {
          principalId: identity.outputs.AZURE_RESOURCE_USER_ASSIGNED_IDENTITY_PRINCIPAL_ID
          principalType: 'ServicePrincipal'
          roleDefinitionIdOrName: 'Azure AI User'
        }
      ]
      networking: {
        aiServicesPrivateDnsZoneResourceId: dns.outputs.dnsZonesOutput.aiServicesDnsZoneResourceId
        cognitiveServicesPrivateDnsZoneResourceId: dns.outputs.dnsZonesOutput.cognitiveServicesDnsZoneResourceId
        openAiPrivateDnsZoneResourceId: dns.outputs.dnsZonesOutput.openAiDnsZoneResourceId
      }
    }
    
  }
}

// https://github.com/Azure/bicep-registry-modules/tree/main/avm/res/machine-learning-services/workspace#readme
module vnet 'modules/aml/virtual-network.bicep' = {
  name: 'aml-vnet-deployment'
  params: {
    location: location
    virtualNetworkName: 'aml-vnet-${resourceToken}'
    securityGroupName: 'aml-nsg-${resourceToken}'
  }
}

module dns 'modules/aml/dns-zones.bicep' = {
  name: 'aml-dns-deployment'
  params: {
    location: location
    vnetResourceId: vnet.outputs.AZURE_VIRTUAL_NETWORK_ID
  }
}

module monitoring 'modules/aml/monitoring.bicep' = {
  name: 'aml-monitoring-deployment'
  params: {
    location: location
    logAnalyticsWorkspaceName: 'aml-log-analytics-${resourceToken}'
    applicationInsightsName: 'aml-app-insights-${resourceToken}'
  }
}

module vault 'modules/aml/key-vault.bicep' = {
  name: 'aml-kv-deployment'
  params: {
    location: location
    name: 'aml-kv-${resourceToken}'
    logAnalyticsWorkspaceId: monitoring.outputs.AZURE_RESOURCE_MONITORING_LOG_ANALYTICS_ID
    userAssignedManagedIdentityPrincipalId: identity.outputs.AZURE_RESOURCE_USER_ASSIGNED_IDENTITY_PRINCIPAL_ID
    secrets: []
    
    privateEndpointName: 'aml-kv-pe'
    privateEndpointSubnetId: vnet.outputs.AZURE_VIRTUAL_NETWORK_PRIVATE_ENDPOINTS_SUBNET_ID
    privateDnsZoneResourceId: dns.outputs.dnsZonesOutput.keyVaultDnsZoneResourceId
  }
}

module storage 'modules/aml/storage-account.bicep' = {
  name: 'aml-storage-deployment'
  params: {
    location: location
    name: 'amlstorage${resourceToken}'
    userAssignedManagedIdentityPrincipalId: identity.outputs.AZURE_RESOURCE_USER_ASSIGNED_IDENTITY_PRINCIPAL_ID
    logAnalyticsWorkspaceId: monitoring.outputs.AZURE_RESOURCE_MONITORING_LOG_ANALYTICS_ID

    blobPrivateDnsZoneResourceId: dns.outputs.dnsZonesOutput.storageBlobDnsZoneResourceId
    filePrivateDnsZoneResourceId: dns.outputs.dnsZonesOutput.storageFileDnsZoneResourceId
    privateEndpointSubnetId: vnet.outputs.AZURE_VIRTUAL_NETWORK_PRIVATE_ENDPOINTS_SUBNET_ID
  }
}

module acr 'modules/aml/container-registry.bicep' = {
  name: 'aml-acr-deployment'
  params: {
    location: location
    name: 'amlacr${resourceToken}'
    logAnalyticsWorkspaceId: monitoring.outputs.AZURE_RESOURCE_MONITORING_LOG_ANALYTICS_ID

    privateEndpointName: 'aml-acr-pe'
    privateEndpointSubnetId: vnet.outputs.AZURE_VIRTUAL_NETWORK_PRIVATE_ENDPOINTS_SUBNET_ID
    privateDnsZoneResourceId: dns.outputs.dnsZonesOutput.acrDnsZoneResourceId
  }
}

// https://github.com/Azure/bicep-registry-modules/tree/main/avm/res/machine-learning-services/workspace#readme
module aml_workspace 'modules/aml/aml.bicep' = {
  name: 'aml-workspace-deployment'
  params: {
    location: location
    name: 'aml-workspace-${resourceToken}'
    userAssignedManagedIdentityId: identity.outputs.AZURE_RESOURCE_USER_ASSIGNED_IDENTITY_ID
    applicationInsightsId: monitoring.outputs.AZURE_RESOURCE_MONITORING_APP_INSIGHTS_ID
    logAnalyticsWorkspaceId: monitoring.outputs.AZURE_RESOURCE_MONITORING_LOG_ANALYTICS_ID
    storageAccountId: storage.outputs.AZURE_STORAGE_ACCOUNT_ID
    containerRegistryId: acr.outputs.AZURE_RESOURCE_REGISTRY_ID
    keyVaultId: vault.outputs.AZURE_RESOURCE_KEY_VAULT_ID
    privateEndpointsSubnetResourceId: vnet.outputs.AZURE_VIRTUAL_NETWORK_AML_SUBNET_ID
    amlPrivateDnsZoneResourceId: dns.outputs.dnsZonesOutput.amlWorkspaceDnsZoneResourceId
    notebooksPrivateDnsZoneResourceId: dns.outputs.dnsZonesOutput.notebooksDnsZoneResourceId

    foundryName: aiFoundry.outputs.aiServicesName
  }
}


// module virtualMachine 'br/public:avm/res/compute/virtual-machine:0.20.0' = if (false) {
//   name: 'virtualMachineDeployment'
//   params: {
//     // Required parameters
//     adminUsername: 'localAdminUser'
//     availabilityZone: -1

//     encryptionAtHost: false
//     imageReference: {
//       offer: '0001-com-ubuntu-server-jammy'
//       publisher: 'Canonical'
//       sku: '22_04-lts-gen2'
//       version: 'latest'
//     }
//     name: 'testing-vm-pka'
//     managedIdentities: {
//       systemAssigned: true
//     }
//     nicConfigurations: [
//       {
//         deleteOption: 'Delete'
//         nicSuffix: '-nic-01'
//         ipConfigurations: [
//           {
//             name: 'ipconfig01'
//             subnetResourceId: vnet.outputs.AZURE_VIRTUAL_NETWORK_PRIVATE_ENDPOINTS_SUBNET_ID
//             pipConfiguration: {
//               availabilityZones: []
//               skuName: 'Basic'
//               skuTier: 'Regional'
//               publicIpNameSuffix: '-pip-01'
//             }
//           }
//         ]
//       }
//     ]
//     osDisk: {
//       deleteOption: 'Delete'
//       caching: 'ReadWrite'
//       diskSizeGB: 32
//       managedDisk: {
//         storageAccountType: 'Standard_LRS'
//       }
//     }
//     osType: 'Linux'
//     vmSize: 'Standard_D2s_v3'
//     // Non-required parameters
//     disablePasswordAuthentication: true
//     location: location
//     publicKeys: [
//       {
//         keyData: loadTextContent('../../../../.ssh/id_rsa.pub')
//         path: '/home/localAdminUser/.ssh/authorized_keys'
//       }
//     ]
//   }
// }

