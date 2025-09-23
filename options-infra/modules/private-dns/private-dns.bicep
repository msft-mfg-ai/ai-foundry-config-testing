import * as types from '../types/types.bicep'

param location string = resourceGroup().location
param vnetResourceIdsForLink string[] = []
param peeringResourceId string[] = []
param hubVnetRanges types.HubVnetRangesType

module virtualNetwork 'br/public:avm/res/network/virtual-network:0.7.0' = {
  name: 'hub-vnet-deployment'
  params: {
    addressPrefixes: [hubVnetRanges.vnetAddressPrefix]
    name: 'hub-vnet'
    location: location
    subnets: [
      {
        name: 'inbound-snet'
        addressPrefix: hubVnetRanges.inboundSubnet
        delegation: 'Microsoft.Network/dnsResolvers'
      }
      {
        name: 'outbound-snet'
        addressPrefix: hubVnetRanges.outboundSubnet
        delegation: 'Microsoft.Network/dnsResolvers'
      }
      {
        name: 'pe-snet'
        addressPrefix: hubVnetRanges.peSubnet
      }
    ]
    peerings: [
      for vnetId in peeringResourceId: {
        remoteVirtualNetworkResourceId: vnetId
        remotePeeringEnabled: true
      }
    ]
  }
}

module dnsResolver 'br/public:avm/res/network/dns-resolver:0.5.4' = {
  name: 'dnsResolverDeployment'
  params: {
    // Required parameters
    name: 'ndrmin001'
    virtualNetworkResourceId: virtualNetwork.outputs.resourceId
    // Non-required parameters
    location: location
    inboundEndpoints: [
      {
        name: 'inbound-endpoint-1'
        subnetResourceId: virtualNetwork.outputs.subnetResourceIds[0] // Use the first subnet (inbound-snet)
        privateIpAddress: hubVnetRanges.privateDnsIp
        privateIpAllocationMethod: 'Static'
      }
    ]
    outboundEndpoints: [
      {
        name: 'outbound-endpoint-1'
        subnetResourceId: virtualNetwork.outputs.subnetResourceIds[1] // Use the second subnet (outbound-snet)
      }
    ]
  }
}

module dnsForwardingRuleset 'br/public:avm/res/network/dns-forwarding-ruleset:0.5.2' = {
  name: 'dnsForwardingRulesetDeployment'
  params: {
    // Required parameters
    dnsForwardingRulesetOutboundEndpointResourceIds: [
      dnsResolver.outputs.outboundEndpointsObject[0].resourceId
    ]
    name: 'forwarding-ruleset'
    forwardingRules: [
      {
        domainName: '.'
        forwardingRuleState: 'Enabled'
        name: 'wildcard'
        targetDnsServers: [
          {
            ipAddress: hubVnetRanges.privateDnsIp
            port: 53
          }
        ]
      }
      {
        domainName: 'azure.com.'
        forwardingRuleState: 'Enabled'
        name: 'azure'
        targetDnsServers: [
          {
            ipAddress: hubVnetRanges.privateDnsIp
            port: 53
          }
        ]
      }
      {
        domainName: 'windows.net.'
        forwardingRuleState: 'Enabled'
        name: 'windows'
        targetDnsServers: [
          {
            ipAddress: hubVnetRanges.privateDnsIp
            port: 53
          }
        ]
      }
    ]
    virtualNetworkLinks: [
      for vnetId in vnetResourceIdsForLink: {
        virtualNetworkResourceId: vnetId
      }
    ]
  }
}

output virtualNetworkId string = virtualNetwork.outputs.resourceId
output peSubnetId string = virtualNetwork.outputs.subnetResourceIds[2]
output peSubnetName string = virtualNetwork.outputs.subnetNames[2]
output privateDnsIp string = hubVnetRanges.privateDnsIp
