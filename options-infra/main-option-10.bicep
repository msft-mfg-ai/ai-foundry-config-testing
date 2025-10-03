// This bicep files deploys simple foundry standard with dependencies in a different region across 3 subscriptions
// Foundry and dependencies - Sub 1
// Private endpoints - Sub 2
// DNS - Sub 3
// App VNET with peering to Foundry VNET
targetScope = 'managementGroup'

param foundryLocation string = 'swedencentral'
param foundrySubscriptionId string
param foundryResourceGroupName string = 'rg-ai-foundry'

param appLocation string = 'westeurope'
param appSubscriptionId string
param appResourceGroupName string = 'rg-ai-apps'

param dnsLocation string = appLocation
param dnsSubscriptionId string = appSubscriptionId
param dnsResourceGroupName string = 'rg-private-dns'

var resourceToken = toLower(uniqueString(managementGroup().id, foundryLocation))

var foundry_rg_id = '/subscriptions/${foundrySubscriptionId}/resourceGroups/${foundryResourceGroupName}'
var app_rg_id = '/subscriptions/${appSubscriptionId}/resourceGroups/${appResourceGroupName}'
var dns_rg_id = '/subscriptions/${dnsSubscriptionId}/resourceGroups/${dnsResourceGroupName}'

var tags = {
  'hidden-link:${foundry_rg_id}': 'Resource'
  'hidden-link:${app_rg_id}': 'Resource'
  'hidden-link:${dns_rg_id}': 'Resource'
  'hidden-title': 'Foundry DNS testing'
}

// first create resource groups for everything
module foundry_rg './modules/basic/resource-group.bicep' = {
  name: 'foundry-rg-deployment'
  scope: subscription(foundrySubscriptionId)
  params: {
    resourceGroupName: foundryResourceGroupName
    location: foundryLocation
    tags: tags
  }
}

module app_rg './modules/basic/resource-group.bicep' = {
  name: 'app-rg-deployment'
  scope: subscription(appSubscriptionId)
  params: {
    resourceGroupName: appResourceGroupName
    location: appLocation
    tags: tags
  }
}

module dns_rg './modules/basic/resource-group.bicep' = {
  name: 'dns-rg-deployment'
  scope: subscription(dnsSubscriptionId)
  params: {
    resourceGroupName: dnsResourceGroupName
    location: dnsLocation
    tags: tags
  }
}

// vnet doesn't have to be in the same RG as the AI Services
// each foundry needs it's own delegated subnet, projects inside of one Foundry share the subnet for the Agents Service
module foundry_vnet './modules/networking/vnet.bicep' = {
  name: 'foundry_vnet'
  scope: resourceGroup(foundrySubscriptionId, foundryResourceGroupName)
  params: {
    vnetName: 'foundry-vnet-${resourceToken}'
    location: foundryLocation
    vnetAddressPrefix: '172.17.0.0/22'
  }
  dependsOn: [foundry_rg]
}

module app_vnet './modules/networking/vnet-with-peering.bicep' = {
  name: 'app-vnet-deployment'
  scope: resourceGroup(appSubscriptionId, appResourceGroupName)
  params: {
    name: 'app-vnet'
    location: appLocation
    vnetAddressPrefix: '172.18.0.0/22'
    peeringResourceIds: [foundry_vnet.outputs.virtualNetworkId]
  }
  dependsOn: [app_rg]
}

module dns_zones './modules/networking/dns-zones.bicep' = {
  name: 'dns-zones-deployment'
  scope: resourceGroup(dnsSubscriptionId, dnsResourceGroupName)
  params: {
    vnetResourceIds: [
      app_vnet.outputs.virtualNetworkId
      foundry_vnet.outputs.virtualNetworkId
    ]
  }
  dependsOn: [dns_rg]
}

module ai_dependencies './modules/ai-dependencies/standard-dependent-resources.bicep' = {
  scope: resourceGroup(foundrySubscriptionId, foundryResourceGroupName)
  params: {
    location: foundryLocation
    azureStorageName: 'projstorage${resourceToken}'
    aiSearchName: 'project-search-${resourceToken}'
    cosmosDBName: 'project-cosmosdb-${resourceToken}'
    // AI Search Service parameters
    aiSearchResourceId: ''
    aiSearchExists: false

    // Storage Account
    azureStorageAccountResourceId: ''
    azureStorageExists: false

    // Cosmos DB Account
    cosmosDBResourceId: ''
    cosmosDBExists: false
  }
}

module privateEndpointAndDNS './modules/networking/private-endpoint-and-dns.bicep' = {
  name: 'private-endpoints-and-dns'
  scope: resourceGroup(appSubscriptionId, appResourceGroupName)
  params: {
    // provide existing DNS zones
    existingDnsZones: dns_zones.outputs.DNSZones

    aiAccountName: foundry.outputs.name
    aiSearchName: ai_dependencies.outputs.aiSearchName // AI Search to secure
    storageName: ai_dependencies.outputs.azureStorageName // Storage to secure
    cosmosDBName: ai_dependencies.outputs.cosmosDBName
    vnetName: app_vnet.outputs.vnetName
    peSubnetName: app_vnet.outputs.peSubnetName
    suffix: resourceToken // Unique identifier
    vnetResourceGroupName: app_vnet.outputs.resourceGroupName // Resource Group for the VNet
    vnetSubscriptionId: app_vnet.outputs.subscriptionId // Subscription ID for the VNet
    cosmosDBSubscriptionId: ai_dependencies.outputs.cosmosDBSubscriptionId // Subscription ID for Cosmos DB
    cosmosDBResourceGroupName: ai_dependencies.outputs.cosmosDBResourceGroupName // Resource Group for Cosmos DB
    aiSearchSubscriptionId: ai_dependencies.outputs.aiSearchServiceSubscriptionId // Subscription ID for AI Search Service
    aiSearchResourceGroupName: ai_dependencies.outputs.aiSearchServiceResourceGroupName // Resource Group for AI Search Service
    storageAccountResourceGroupName: ai_dependencies.outputs.azureStorageResourceGroupName // Resource Group for Storage Account
    storageAccountSubscriptionId: ai_dependencies.outputs.azureStorageSubscriptionId // Subscription ID for Storage Account
    aiAccountNameResourceGroup: foundry.outputs.resourceGroupName
    aiAccountSubscriptionId: foundry.outputs.subscriptionId
  }
}

// --------------------------------------------------------------------------------------------------------------
// -- Log Analytics Workspace and App Insights ------------------------------------------------------------------
// --------------------------------------------------------------------------------------------------------------
module logAnalytics './modules/monitor/loganalytics.bicep' = {
  scope: resourceGroup(foundrySubscriptionId, foundryResourceGroupName)
  name: 'log-analytics'
  params: {
    newLogAnalyticsName: 'log-analytics'
    newApplicationInsightsName: 'app-insights'
  }
}

module foundry './modules/ai/ai-foundry.bicep' = {
  scope: resourceGroup(foundrySubscriptionId, foundryResourceGroupName)
  name: 'ai-foundry-deployment'
  params: {
    managedIdentityId: '' // Use System Assigned Identity
    name: 'ai-foundry-${resourceToken}'
    appInsightsName: logAnalytics.outputs.applicationInsightsName
    publicNetworkAccess: 'Enabled'
    agentSubnetId: foundry_vnet.outputs.agentSubnetId
    deployments: [
      {
        name: 'gpt-4.1-mini'
        properties: {
          model: {
            format: 'OpenAI'
            name: 'gpt-4.1-mini'
            version: '2025-04-14'
          }
        }
        sku: {
          name: 'GlobalStandard'
          capacity: 20
        }
      }
    ]
  }
}

module project1 './modules/ai/ai-project-with-caphost.bicep' = {
  scope: resourceGroup(foundrySubscriptionId, foundryResourceGroupName)
  name: 'ai-project-1-with-caphost-${resourceToken}'
  params: {
    foundryName: foundry.outputs.name
    location: foundryLocation
    projectId: 1
    aiDependencies: ai_dependencies.outputs.aiDependencies
  }
}

module virtualMachine 'br/public:avm/res/compute/virtual-machine:0.20.0' = if (true) {
  name: 'virtualMachineDeployment'
  scope: resourceGroup(appSubscriptionId, appResourceGroupName)
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
            subnetResourceId: app_vnet.outputs.peSubnetId
            pipConfiguration: {
              availabilityZones: []
              skuName: 'Basic'
              skuTier: 'Regional'
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
    vmSize: 'Standard_D2als_v6'
    // Non-required parameters
    disablePasswordAuthentication: true
    location: appLocation
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
