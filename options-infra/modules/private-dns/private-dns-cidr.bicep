import * as types from '../types/types.bicep'

param vnetAddressPrefix string = '172.168.0.0/16'

var defaultVnetAddressPrefix = '172.168.0.0/16'
var vnetAddress = empty(vnetAddressPrefix) ? defaultVnetAddressPrefix : vnetAddressPrefix
var inboundSubnet = cidrSubnet(vnetAddress, 27, 0)
var outboundSubnet = cidrSubnet(vnetAddress, 27, 1)
var peSubnet = cidrSubnet(vnetAddress, 27, 2)
var inboundPrivateIp = cidrHost(inboundSubnet, 5)



output hubVnetRanges types.HubVnetRangesType = {
  inboundSubnet: inboundSubnet
  outboundSubnet: outboundSubnet
  peSubnet: peSubnet
  privateDnsIp: inboundPrivateIp
  vnetAddressPrefix: vnetAddress
}
