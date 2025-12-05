/*
Virtual Network Module
This module deploys the core network infrastructure with security controls:

1. Address Space:
   - VNet CIDR: 172.16.0.0/16 OR 192.168.0.0/16
   - Agents Subnet: 172.16.0.0/24 OR 192.168.0.0/24
   - Private Endpoint Subnet: 172.16.101.0/24 OR 192.168.1.0/24

2. Security Features:
   - Network isolation
   - Subnet delegation
   - Private endpoint subnet
*/

@description('Azure region for the deployment')
param location string

@description('The name of the virtual network')
param vnetName string = 'agents-vnet-test'

@description('The name of Agents Subnet')
param agentSubnetName string = 'agent-subnet'

@description('The name of Hub subnet')
param peSubnetName string = 'pe-subnet'

@description('The name of Hub subnet')
param appGwSubnetName string = 'appgw-subnet'

@description('Address space for the VNet')
param vnetAddressPrefix string = ''

@description('Address prefix for the agent subnet')
param agentSubnetPrefix string = ''
param extraAgentSubnets int = 0 // Number of additional agent subnets to create

param customDNS string = ''

@description('Address prefix for the private endpoint subnet')
param peSubnetPrefix string = ''
@description('Address prefix for the application gateway subnet')
param appGwSubnetPrefix string = ''

var defaultVnetAddressPrefix = '192.168.0.0/16'
var vnetAddress = empty(vnetAddressPrefix) ? defaultVnetAddressPrefix : vnetAddressPrefix
var agentSubnet = empty(agentSubnetPrefix) ? cidrSubnet(vnetAddress, 24, 0) : agentSubnetPrefix
var peSubnet = empty(peSubnetPrefix) ? cidrSubnet(vnetAddress, 24, 1) : peSubnetPrefix
var appGwSubnet = empty(appGwSubnetPrefix) ? cidrSubnet(vnetAddress, 24, extraAgentSubnets + 3) : appGwSubnetPrefix

// Temporary
var laSubnet = empty(peSubnetPrefix) ? cidrSubnet(vnetAddress, 24, 2) : peSubnetPrefix
var laSubnetName = 'logic-apps-subnet'

var extraAgentSubnetNames = [for i in range(0, extraAgentSubnets): '${agentSubnetName}-${i + 1}']
var extraAgentSubnetObjects = [
  for i in range(0, extraAgentSubnets): {
    name: extraAgentSubnetNames[i]
    properties: {
      addressPrefix: cidrSubnet(vnetAddress, 24, i + 3) // Start from 3 to avoid conflicts with agent and PE subnets
      delegations: [
        {
          name: 'Microsoft.app/environments'
          properties: {
            serviceName: 'Microsoft.App/environments'
          }
        }
      ]
    }
  }
]

module networkSecurityGroup 'br/public:avm/res/network/network-security-group:0.5.1' = {
  name: 'networkSecurityGroupDeployment'
  params: {
    name: 'agent-nsg'
  }
}

module appGwSecurityGroup 'br/public:avm/res/network/network-security-group:0.5.1' = {
  name: 'appGwSecurityGroupDeployment'
  params: {
    name: 'appgw-nsg'
    securityRules: [
      // Required: Allow Application Gateway V2 infrastructure communication
      {
        name: 'AllowGatewayManagerInbound'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'GatewayManager'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '65200-65535'
          description: 'Required for Application Gateway V2 infrastructure communication'
        }
      }
      // Required: Allow Azure Load Balancer health probes
      {
        name: 'AllowAzureLoadBalancerInbound'
        properties: {
          priority: 110
          direction: 'Inbound'
          access: 'Allow'
          protocol: '*'
          sourceAddressPrefix: 'AzureLoadBalancer'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
          description: 'Required for Azure Load Balancer health probes'
        }
      }
      // Allow HTTPS traffic from internet (for public-facing App Gateway)
      {
        name: 'AllowHttpsInbound'
        properties: {
          priority: 200
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'Internet'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '443'
          description: 'Allow HTTPS traffic'
        }
      }
      // Allow HTTP traffic (optional - for redirect to HTTPS)
      {
        name: 'AllowHttpInbound'
        properties: {
          priority: 210
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'Internet'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '80'
          description: 'Allow HTTP traffic (for HTTPS redirect)'
        }
      }
    ]
  }
}

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddress
      ]
    }
    dhcpOptions: empty(customDNS)
      ? null
      : {
          dnsServers: [
            customDNS
          ]
        }
    subnets: union(extraAgentSubnetObjects, [
      {
        name: agentSubnetName
        properties: {
          addressPrefix: agentSubnet
          delegations: [
            {
              name: 'Microsoft.app/environments'
              properties: {
                serviceName: 'Microsoft.App/environments'
              }
            }
          ]
          networkSecurityGroup: {
            id: networkSecurityGroup.outputs.resourceId
          }
        }
      }
      {
        name: peSubnetName
        properties: {
          addressPrefix: peSubnet
          networkSecurityGroup: {
            id: networkSecurityGroup.outputs.resourceId
          }
        }
      }
      {
        name: appGwSubnetName
        properties: {
          addressPrefix: appGwSubnet
          networkSecurityGroup: {
            id: appGwSecurityGroup.outputs.resourceId
          }
        }
      }
      {
        name: laSubnetName
        properties: {
          addressPrefix: laSubnet
          networkSecurityGroup: {
            id: networkSecurityGroup.outputs.resourceId
          }
          delegations: [
            {
              name: 'Microsoft.Web/serverfarms'
              properties: {
                serviceName: 'Microsoft.Web/serverfarms'
              }
            }
          ]
        }
      }
    ])
  }
}
// Output variables
output peSubnetName string = peSubnetName
output agentSubnetName string = agentSubnetName
output appGwSubnetName string = appGwSubnetName
output agentSubnetId string = '${virtualNetwork.id}/subnets/${agentSubnetName}'
output peSubnetId string = '${virtualNetwork.id}/subnets/${peSubnetName}'
output appGwSubnetId string = '${virtualNetwork.id}/subnets/${appGwSubnetName}'
output virtualNetworkName string = virtualNetwork.name
output virtualNetworkId string = virtualNetwork.id
output virtualNetworkResourceGroup string = resourceGroup().name
output virtualNetworkSubscriptionId string = subscription().subscriptionId
output extraAgentSubnetNames array = extraAgentSubnetNames
output extraAgentSubnetIds array = [for name in extraAgentSubnetNames: '${virtualNetwork.id}/subnets/${name}']
