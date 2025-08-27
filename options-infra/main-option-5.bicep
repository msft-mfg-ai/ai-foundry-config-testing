// This bicep files deploys simple foundry standard
targetScope = 'resourceGroup'

param location string = resourceGroup().location


var resourceToken = toLower(uniqueString(resourceGroup().id, location))

// vnet doesn't have to be in the same RG as the AI Services
// each agent needs it's own delegated subnet, which means we need as many subnets as agents
module vnet './modules/networking/vnet.bicep' = {
  name: 'vnet'
  params: {
    vnetName: 'project-vnet-${resourceToken}'
    location: location
    vnetAddressPrefix: '172.0.0.0/16'
  }
}

module privateDns './modules/private-dns/private-dns.bicep' = {
  name: 'private-dns'
  params: {
    location: location
    vnetAddressPrefix: '172.168.0.0/16'
    vnetResourceIdsForLink: [
      vnet.outputs.virtualNetworkId
    ]
  }
}

module ai_dependencies './modules/ai/ai-dependencies-with-dns.bicep' = {
  name: 'ai-dependencies-with-dns'
  params: {
    peSubnetName: privateDns.outputs.peSubnetName
    vnetResourceId: privateDns.outputs.virtualNetworkId
    resourceToken: resourceToken
    aiServicesName: '' // create AI serviced PE later
    aiAccountNameResourceGroupName: ''
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
