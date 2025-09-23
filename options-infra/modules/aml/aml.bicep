param location string = resourceGroup().location
param name string

param logAnalyticsWorkspaceId string
param applicationInsightsId string
param keyVaultId string
param userAssignedManagedIdentityId string
param storageAccountId string

param amlPrivateDnsZoneResourceId string
param notebooksPrivateDnsZoneResourceId string

param privateEndpointsSubnetResourceId string
param containerRegistryId string

param foundryName string?

@allowed([
  'Default'
  'Hub'
])
param kind string = 'Default' //'Hub'
var description string = '${kind == 'Hub' ? 'Ai Foundry Hub' : 'Machine Learning Workspace'} ${name}'
var friendlyName string = description

// resource aiServicesConnection 'connections@2024-04-01-preview' = {
//   name: '${name}-connection'
//   properties: {
//     category: 'AIServices'
//     target: aiServicesTarget
//     authType: 'AAD'
//     isSharedToAll: true
//     metadata: {
//       ApiType: 'Azure'
//       ResourceId: aiServicesId
//     }
//   }
// }

module workspace 'br/public:avm/res/machine-learning-services/workspace:0.13.0' = {
  name: 'ml-workspace-Deployment'
  params: {
    // Required parameters
    name: name
    sku: 'Basic'
    // Non-required parameters
    friendlyName: friendlyName
    description: description
    associatedApplicationInsightsResourceId: applicationInsightsId
    associatedKeyVaultResourceId: keyVaultId
    associatedStorageAccountResourceId: storageAccountId
    associatedContainerRegistryResourceId: containerRegistryId
    diagnosticSettings: [
      {
        workspaceResourceId: logAnalyticsWorkspaceId
      }
    ]
    managedIdentities: {
      userAssignedResourceIds: [
        userAssignedManagedIdentityId
      ]
    }
    primaryUserAssignedIdentity: userAssignedManagedIdentityId
    provisionNetworkNow: true
    publicNetworkAccess: 'Disabled'

    location: location
    managedNetworkSettings: {
      firewallSku: 'Standard'

      isolationMode: 'AllowOnlyApprovedOutbound'
      outboundRules: {
        // rule1: {
        //   category: 'UserDefined'
        //   destination: {
        //     serviceResourceId: '<serviceResourceId>'
        //     sparkEnabled: true
        //     subresourceTarget: 'blob'
        //   }
        //   type: 'PrivateEndpoint'
        // }
        rule2: {
          category: 'UserDefined'
          destination: 'pypi.org'
          type: 'FQDN'
        }
        rule3: {
          category: 'UserDefined'
          destination: {
            portRanges: '80,443'
            protocol: 'TCP'
            serviceTag: 'AppService'
          }
          type: 'ServiceTag'
        }
      }
    }
    privateEndpoints: [
      {
        privateDnsZoneGroup: {
          privateDnsZoneGroupConfigs: [
            {
              privateDnsZoneResourceId: amlPrivateDnsZoneResourceId
            }
            {
              privateDnsZoneResourceId: notebooksPrivateDnsZoneResourceId
            }
          ]
        }
        subnetResourceId: privateEndpointsSubnetResourceId
        tags: {
          Environment: 'Non-Prod'
          'hidden-title': 'Test AML Deployment'
          Role: 'DeploymentValidation'
        }
      }
    ]
    connections: empty(foundryName)
      ? []
      : [
          {
            name: 'aiServicesConnection'
            category: 'AzureOpenAI'
            group: 'AzureAI'
            connectionProperties: {
              authType: 'AAD'
            }
            target: 'https://${foundryName!}.openai.azure.com/'
            isSharedToAll: true
            metadata: {
              ApiType: 'Azure'
              ResourceId: resourceId('Microsoft.CognitiveServices/accounts', foundryName!)
            }
          }
          {
            name: 'aiServicesConnection'
            category: 'AIServices'
            group: 'AzureAI'
            connectionProperties: {
              authType: 'AAD'
            }
            target: 'https://${foundryName!}.cognitiveservices.azure.com/'
            isSharedToAll: true
            metadata: {
              ApiType: 'Azure'
              ResourceId: resourceId('Microsoft.CognitiveServices/accounts', foundryName!)
            }
          }
        ]
    // sharedPrivateLinkResources: [
    //   {
    //     name: '<name>'
    //     groupId: 'amlworkspace'
    //     privateDnsZoneId: '<privateDnsZoneResourceId>'
    //     roleAssignments: [
    //       {
    //         principalId: '<principalId>'
    //         principalType: 'ServicePrincipal'
    //         roleDefinitionIdOrName: 'Reader'
    //       }
    //     ]
    //   }
    // ]
    systemDatastoresAuthMode: 'Identity'
    tags: {
      Environment: 'Non-Prod'
      'hidden-title': 'Test AML Deployment'
      Role: 'DeploymentValidation'
    }
  }
}
