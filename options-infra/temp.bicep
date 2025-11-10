param location string = resourceGroup().location
param resourceToken string = uniqueString(resourceGroup().id, location)

module defaultNetworkSecurityGroup 'br/public:avm/res/network/network-security-group:0.5.1' =  {
  name: 'default-network-security-group'
  params: {
    name: 'foundry-nsg'
    location: location
    securityRules: []
  }
}

module virtualNetwork 'br/public:avm/res/network/virtual-network:0.7.0' =  {
  name: 'virtual-network-${resourceToken}'
  params: {
    addressPrefixes: ['10.0.0.0/26']
    name: 'foundry-vnet'
    location: location
    subnets: [
      {
        name: 'agents-subnet'
        addressPrefix: '10.0.0.0/27'
        networkSecurityGroupResourceId: defaultNetworkSecurityGroup!.outputs.resourceId
      }
      {
        name: 'private-endpoints-subnet'
        addressPrefix: '10.0.0.32/27'
        networkSecurityGroupResourceId: defaultNetworkSecurityGroup!.outputs.resourceId
      }
    ]
  }
}

module aiFoundry 'br/public:avm/ptn/ai-ml/ai-foundry:0.5.0' = {
  name: 'aiFoundryDeployment'
  params: {
    // Required parameters
    baseName: take('foundry-${resourceToken}', 12)
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
    // second subnet for private endpoints
    privateEndpointSubnetResourceId: virtualNetwork.outputs.subnetResourceIds[1]
    aiFoundryConfiguration: {
      disableLocalAuth: true
      roleAssignments: [
        // {
        //   principalId: identity.outputs.AZURE_RESOURCE_USER_ASSIGNED_IDENTITY_PRINCIPAL_ID
        //   principalType: 'ServicePrincipal'
        //   // roleDefinitionIdOrName: 'Azure AI User'
        //   roleDefinitionIdOrName: '/providers/Microsoft.Authorization/roleDefinitions/53ca6127-db72-4b80-b1b0-d745d6d5456d'
        // }
      ]
      // networking: {
      //   aiServicesPrivateDnsZoneResourceId: dns.outputs.dnsZonesOutput.aiServicesDnsZoneResourceId
      //   cognitiveServicesPrivateDnsZoneResourceId: dns.outputs.dnsZonesOutput.cognitiveServicesDnsZoneResourceId
      //   openAiPrivateDnsZoneResourceId: dns.outputs.dnsZonesOutput.openAiDnsZoneResourceId
      // }
    }
  }
}
