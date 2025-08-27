param location string = resourceGroup().location
param vnetAddressPrefix string = '172.168.0.0/16'
param vnetResourceIdsForLink string[] = []

var defaultVnetAddressPrefix = '172.168.0.0/16'
var vnetAddress = empty(vnetAddressPrefix) ? defaultVnetAddressPrefix : vnetAddressPrefix
var inboundSubnet = cidrSubnet(vnetAddress, 27, 0)
var outboundSubnet = cidrSubnet(vnetAddress, 27, 1)
var peSubnet = cidrSubnet(vnetAddress, 27, 2)
var inboundPrivateIp = cidrHost(inboundSubnet, 5)

module virtualNetwork 'br/public:avm/res/network/virtual-network:0.7.0' = {
  name: 'name'
  params: {
    addressPrefixes: [defaultVnetAddressPrefix]
    name: 'hub-vnet'
    location: location
    subnets: [
      {
        name: 'inbound-snet'
        addressPrefix: inboundSubnet
        delegation: 'Microsoft.Network/dnsResolvers'
      }
      {
        name: 'outbound-snet'
        addressPrefix: outboundSubnet
        delegation: 'Microsoft.Network/dnsResolvers'
      }
      {
        name: 'pe-snet'
        addressPrefix: peSubnet
      }
    ]
    peerings: [
      {
        remoteVirtualNetworkResourceId: vnetResourceIdsForLink[0]
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
        privateIpAddress: inboundPrivateIp
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
            ipAddress: inboundPrivateIp
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
            ipAddress: inboundPrivateIp
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
            ipAddress: inboundPrivateIp
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
