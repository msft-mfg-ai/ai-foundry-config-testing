param name string
param location string = resourceGroup().location
param applicationGatewaySubnetId string
param publicIpResourceId string

param applicationFqdn string
param acaName string = 'aca'

var cleanFqdn = replace(replace(applicationFqdn, 'https://', ''), 'http://', '')

module applicationGateway 'br/public:avm/res/network/application-gateway:0.7.2' = {
  params: {
    // Required parameters
    name: name
    capacity: 1
    availabilityZones: []
    // Non-required parameters
    backendAddressPools: [
      {
        name: 'acaBackendPool'
        properties: {
          backendAddresses: [
            {
              fqdn: cleanFqdn
            }
          ]
        }
      }
    ]
    backendHttpSettingsCollection: [
      {
        name: 'acaBackendHttpsSetting'
        properties: {
          cookieBasedAffinity: 'Disabled'
          pickHostNameFromBackendAddress: true
          port: 443
          protocol: 'Https'
          requestTimeout: 30
        }
      }
    ]
    enableHttp2: true
    enableTelemetry: null
    frontendIPConfigurations: [
      {
        name: 'public'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: publicIpResourceId
          }
        }
      }
    ]
    frontendPorts: [
      {
        name: 'port443'
        properties: {
          port: 443
        }
      }
      {
        name: 'port80'
        properties: {
          port: 80
        }
      }
    ]
    gatewayIPConfigurations: [
      {
        name: 'apw-ip-configuration'
        properties: {
          subnet: {
            id: applicationGatewaySubnetId
          }
        }
      }
    ]
    httpListeners: [
      {
        name: 'my-agw-listener-http'
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/applicationGateways/frontendIPConfigurations', name, 'public')
          }
          frontendPort: {
            id: resourceId('Microsoft.Network/applicationGateways/frontendPorts', name, 'port80')
          }
          hostNames: []
          protocol: 'http'
          requireServerNameIndication: false
          // sslCertificate: {
          //   id: '<id>'
          // }
        }
      }
    ]
    location: location
    // managedIdentities: {
    //   userAssignedResourceIds: [
    //     '<managedIdentityResourceId>'
    //   ]
    // }
    redirectConfigurations: [
      // {
      //   name: 'httpRedirect80'
      //   properties: {
      //     includePath: true
      //     includeQueryString: true
      //     redirectType: 'Permanent'
      //     requestRoutingRules: [
      //       {
      //         id: '<id>'
      //       }
      //     ]
      //     targetListener: {
      //       id: '<id>'
      //     }
      //   }
      // }
    ]
    requestRoutingRules: [
      {
        name: 'public80-appServiceBackendHttpsSetting-appServiceBackendHttpsSetting'
        properties: {
          backendAddressPool: {
            id: resourceId('Microsoft.Network/applicationGateways/backendAddressPools', name, 'acaBackendPool')
          }
          backendHttpSettings: {
            id: resourceId('Microsoft.Network/applicationGateways/backendHttpSettingsCollection', name, 'acaBackendHttpsSetting')
          }
          httpListener: {
            id: resourceId('Microsoft.Network/applicationGateways/httpListeners', name, 'my-agw-listener-http')
          }
          priority: 200
          ruleType: 'Basic'
        }
      }
      // {
      //   name: 'httpRedirect80-public443'
      //   properties: {
      //     httpListener: {
      //       id: '<id>'
      //     }
      //     priority: 300
      //     redirectConfiguration: {
      //       id: '<id>'
      //     }
      //     ruleType: 'Basic'
      //   }
      // }
    ]
    rewriteRuleSets: [
      // {
      //   id: '<id>'
      //   name: 'customRewrite'
      //   properties: {
      //     rewriteRules: [
      //       {
      //         actionSet: {
      //           requestHeaderConfigurations: [
      //             {
      //               headerName: 'Content-Type'
      //               headerValue: 'JSON'
      //             }
      //             {
      //               headerName: 'someheader'
      //             }
      //           ]
      //           responseHeaderConfigurations: []
      //         }
      //         conditions: []
      //         name: 'NewRewrite'
      //         ruleSequence: 100
      //       }
      //     ]
      //   }
      // }
    ]
    sku: 'Standard_v2'
    sslCertificates: [
      // {
      //   name: 'az-apgw-x-001-ssl-certificate'
      //   properties: {
      //     keyVaultSecretId: '<keyVaultSecretId>'
      //   }
      // }
    ]
    tags: {
      Environment: 'Non-Prod'
      'hidden-title': 'App Gateway for ${acaName}'
      Role: 'DeploymentValidation'
    }
  }
}
