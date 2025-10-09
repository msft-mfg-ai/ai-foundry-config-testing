// TODO - deployment using verified modules
targetScope = 'resourceGroup'

param location string = resourceGroup().location

param user_principal_id string = ''

var resourceToken = toLower(uniqueString(resourceGroup().id, location))

// vnet doesn't have to be in the same RG as the AI Services
// each foundry needs it's own delegated subnet, projects inside of one Foundry share the subnet for the Agents Service
module vnet './modules/networking/vnet.bicep' = {
  name: 'vnet'
  params: {
    vnetName: 'project-vnet-${resourceToken}'
    location: location
    vnetAddressPrefix: '172.17.0.0/22'
  }
}

module dns_zones './modules/networking/dns-zones.bicep' = {
  name: 'dns-zones-deployment'
  params: {
    vnetResourceIds: [
      vnet.outputs.virtualNetworkId
    ]
  }
}


// --------------------------------------------------------------------------------------------------------------
// -- Log Analytics Workspace and App Insights ------------------------------------------------------------------
// --------------------------------------------------------------------------------------------------------------
module logAnalytics './modules/monitor/loganalytics.bicep' = {
  name: 'log-analytics'
  params: {
    newLogAnalyticsName: 'log-analytics'
    newApplicationInsightsName: 'app-insights'
    location: location
  }
}

module aiFoundry 'br/public:avm/ptn/ai-ml/ai-foundry:0.3.0' = {
  name: 'aiFoundryDeployment'
  params: {
    // Required parameters
    baseName: 'foundry'
    // Non-required parameters
    aiFoundryConfiguration: {
      allowProjectManagement: true
      createCapabilityHosts: true
      location: location
      networking: {
        aiServicesPrivateDnsZoneResourceId: dns_zones.outputs.aiServicesPrivateDnsZoneId
        cognitiveServicesPrivateDnsZoneResourceId: dns_zones.outputs.cognitiveServicesPrivateDnsZoneId
        openAiPrivateDnsZoneResourceId: dns_zones.outputs.openAiPrivateDnsZoneId
      }
      project: {
        name: 'ai-project-1'
        displayName: 'AI Project 1'
        desc: 'This is a description for AI Project 1'
      }
      roleAssignments: [
        {
          principalId: '<principalId>'
          principalType: 'ServicePrincipal'
          roleDefinitionIdOrName: 'Cognitive Services OpenAI User'
        }
      ]
    }
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
    aiSearchConfiguration: {
      name: '<name>'
      privateDnsZoneResourceId: '<privateDnsZoneResourceId>'
      roleAssignments: [
        {
          principalId: '<principalId>'
          principalType: 'ServicePrincipal'
          roleDefinitionIdOrName: 'Search Index Data Contributor'
        }
      ]
    }
    cosmosDbConfiguration: {
      name: '<name>'
      privateDnsZoneResourceId: '<privateDnsZoneResourceId>'
      roleAssignments: [
        {
          principalId: '<principalId>'
          principalType: 'ServicePrincipal'
          roleDefinitionIdOrName: 'Cosmos DB Account Reader Role'
        }
      ]
    }
    includeAssociatedResources: true
    keyVaultConfiguration: {
      name: '<name>'
      privateDnsZoneResourceId: '<privateDnsZoneResourceId>'
      roleAssignments: [
        {
          principalId: '<principalId>'
          principalType: 'ServicePrincipal'
          roleDefinitionIdOrName: 'Key Vault Secrets User'
        }
      ]
    }
    location: '<location>'
    lock: {
      kind: 'CanNotDelete'
      name: '<name>'
    }
    privateEndpointSubnetResourceId: '<privateEndpointSubnetResourceId>'
    storageAccountConfiguration: {
      blobPrivateDnsZoneResourceId: '<blobPrivateDnsZoneResourceId>'
      name: '<name>'
      roleAssignments: [
        {
          principalId: '<principalId>'
          principalType: 'ServicePrincipal'
          roleDefinitionIdOrName: 'Storage Blob Data Contributor'
        }
      ]
    }
    tags: {
      Environment: 'Example'
      'hidden-title': 'This is visible in the resource name'
      Role: 'DeploymentValidation'
    }
  }
}

module foundry './modules/ai/ai-foundry.bicep' = {
  name: 'foundry-shared'
  params: {
    managedIdentityId: '' // Use System Assigned Identity
    name: 'ai-foundry-${resourceToken}'
    location: location
    appInsightsName: logAnalytics.outputs.applicationInsightsName
    publicNetworkAccess: 'Enabled'
    agentSubnetId: vnet.outputs.agentSubnetId // Use the first agent subnet
    deployments: [

    ]
  }
}

module project1 './modules/ai/ai-project-with-caphost.bicep' = {
  name: 'ai-project-1-with-caphost-${resourceToken}'
  params: {
    foundryName: foundry.outputs.name
    location: location
    projectId: 1
    aiDependencies: ai_dependencies.outputs.aiDependencies
  }
}

module virtualMachine 'br/public:avm/res/compute/virtual-machine:0.18.0' = {
  name: 'virtualMachineDeployment'
  params: {
    // Required parameters
    adminUsername: 'localAdminUser'
    availabilityZone: -1
    encryptionAtHost: false
    imageReference: {
      offer: '0001-com-ubuntu-server-jammy'
      publisher: 'Canonical'
      sku: '22_04-lts-gen2'
      version: 'latest'
    }
    name: 'testing-vm-pka'
    managedIdentities: {
      systemAssigned: true
    }
    nicConfigurations: [
      {
        deleteOption: 'Delete'
        nicSuffix: '-nic-01'
        ipConfigurations: [
          {
            name: 'ipconfig01'
            subnetResourceId: vnet.outputs.peSubnetId
            pipConfiguration: {
              publicIpNameSuffix: '-pip-01'
            }
          }
        ]
      }
    ]
    osDisk: {
      deleteOption: 'Delete'
      caching: 'ReadWrite'
      diskSizeGB: 32
      managedDisk: {
        storageAccountType: 'Standard_LRS'
      }
    }
    osType: 'Linux'
    vmSize: 'Standard_D2s_v3'
    // Non-required parameters
    disablePasswordAuthentication: true
    location: location
    publicKeys: [
      {
        keyData: loadTextContent('../../../../.ssh/id_rsa.pub')
        path: '/home/localAdminUser/.ssh/authorized_keys'
      }
    ]
  }
}

output capability1HostUrl string = project1.outputs.capabilityHostUrl
output ai1ConnectionUrl string = project1.outputs.aiConnectionUrl
output foundry1_connection_string string = project1.outputs.foundry_connection_string
