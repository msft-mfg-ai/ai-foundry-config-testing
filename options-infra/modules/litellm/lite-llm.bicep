param location string
param resourceToken string
param appInsightsConnectionString string
param logAnalyticsWorkspaceResourceId string
param identityResourceId string
@secure()
param openAiApiKey string
param openAiApiBase string
param aiFoundryName string

param acaSubnetResourceId string
param privateEndpointSubnetId string
param virtualNetworkResourceId string
param keyVaultDnsZoneResourceId string
param postgressDnsZoneResourceId string

param liteLlmConfigYaml string
param litlLlmPublicFqdn string?

var identityResourceParts = split(identityResourceId, '/')
var identityResourceName = last(identityResourceParts)
var identityResourceRgName = identityResourceParts[length(identityResourceParts) - 5]
var identityResourceSubId = identityResourceParts[2]

resource userAssignedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2018-11-30' existing = {
  name: identityResourceName
  scope: resourceGroup(identityResourceSubId, identityResourceRgName)
}

var litelLlmasterkey = take(uniqueString(resourceToken, 'litellm'), 6)

module postgressDb '../db/postgress.bicep' = {
  name: 'postgress-db-deployment'
  params: {
    location: location
    name: 'pg-${resourceToken}'
    keyVaultName: keyVault.outputs.AZURE_RESOURCE_KEY_VAULT_NAME
    workspaceResourceId: logAnalyticsWorkspaceResourceId
    privateEndpointSubnetId: privateEndpointSubnetId
    privateDnsZoneResourceId: postgressDnsZoneResourceId
  }
}

module managedEnvironment '../aca/container-app-environment.bicep' = {
  name: 'managed-environment'
  params: {
    location: location
    appInsightsConnectionString: appInsightsConnectionString
    name: 'aca${resourceToken}'
    logAnalyticsWorkspaceResourceId: logAnalyticsWorkspaceResourceId
    storages: []
    publicNetworkAccess: 'Disabled'
    infrastructureSubnetId: acaSubnetResourceId
  }
}

module keyVault '../kv/key-vault.bicep' = {
  name: 'key-vault-deployment'
  params: {
    tags: {}
    location: location
    name: 'kv-${resourceToken}'
    secrets: [
      { name: 'openaiapikey', value: openAiApiKey }
      { name: 'litelLlmasterkey', value: litelLlmasterkey }
    ]
    userAssignedManagedIdentityPrincipalId: userAssignedIdentity.properties.principalId
    principalId: null
    doRoleAssignments: true
    logAnalyticsWorkspaceId: logAnalyticsWorkspaceResourceId

    publicAccessEnabled: false
    privateEndpointSubnetId: privateEndpointSubnetId
    privateEndpointName: 'pe-kv-${resourceToken}'
    privateDnsZoneResourceId: keyVaultDnsZoneResourceId
  }
}

module dnsAca 'br/public:avm/res/network/private-dns-zone:0.7.1' = {
  name: 'dns-aca'
  params: {
    name: 'privatelink.${location}.azurecontainerapps.io'
    virtualNetworkLinks: [
      {
        virtualNetworkResourceId: virtualNetworkResourceId
      }
    ]
  }
}

// private endpoints for external APIs
module acaPrivateEndpoint '../networking/private-endpoint.bicep' = {
  name: 'private-endpoint-aca'
  params: {
    privateEndpointName: 'pe-${managedEnvironment.outputs.AZURE_RESOURCE_CONTAINER_APPS_ENVIRONMENT_NAME}'
    location: location
    subnetId: privateEndpointSubnetId
    targetResourceId: managedEnvironment.outputs.AZURE_RESOURCE_CONTAINER_APPS_ENVIRONMENT_ID
    groupIds: ['managedEnvironments']
    zoneConfigs: [
      {
        name: dnsAca.outputs.name
        privateDnsZoneId: dnsAca.outputs.resourceId
      }
    ]
  }
}

module appMcp '../aca/container-app.bicep' = {
  name: 'app-mcp'
  params: {
    location: location
    name: 'aca-mcp-${resourceToken}'
    workloadProfileName: managedEnvironment.outputs.AZURE_RESOURCE_CONTAINER_APPS_WORKLOAD_PROFILE_NAME
    applicationInsightsConnectionString: appInsightsConnectionString
    definition: {
      settings: []
    }
    ingressTargetPort: 3000
    existingImage: 'ghcr.io/karpikpl/sample-mcp-fastmcp-python:main'
    userAssignedManagedIdentityClientId: userAssignedIdentity.properties.clientId
    userAssignedManagedIdentityResourceId: userAssignedIdentity.id
    ingressExternal: true
    cpu: '0.25'
    memory: '0.5Gi'
    scaleMaxReplicas: 1
    scaleMinReplicas: 1
    containerAppsEnvironmentResourceId: managedEnvironment.outputs.AZURE_RESOURCE_CONTAINER_APPS_ENVIRONMENT_ID
    keyVaultName: null
    probes: [
      {
        type: 'Readiness'
        httpGet: {
          path: '/health'
          port: 3000
        }
      }
    ]
  }
}

module appOpenAPI '../aca/container-app.bicep' = {
  name: 'app-openapi'
  params: {
    location: location
    name: 'aca-openapi-${resourceToken}'
    workloadProfileName: managedEnvironment.outputs.AZURE_RESOURCE_CONTAINER_APPS_WORKLOAD_PROFILE_NAME
    applicationInsightsConnectionString: appInsightsConnectionString
    definition: {
      settings: []
    }
    ingressTargetPort: 3000
    existingImage: 'ghcr.io/karpikpl/wttr-docker:main'
    userAssignedManagedIdentityClientId: userAssignedIdentity.properties.clientId
    userAssignedManagedIdentityResourceId: userAssignedIdentity.id
    ingressExternal: true
    cpu: '0.25'
    memory: '0.5Gi'
    scaleMaxReplicas: 1
    scaleMinReplicas: 1
    containerAppsEnvironmentResourceId: managedEnvironment.outputs.AZURE_RESOURCE_CONTAINER_APPS_ENVIRONMENT_ID
    keyVaultName: null
    probes: [
      {
        type: 'Readiness'
        httpGet: {
          path: '/health'
          port: 3000
        }
      }
    ]
  }
}

module liteLlmApp '../aca/container-app.bicep' = {
  name: 'app-litellm'
  params: {
    location: location
    name: 'aca-litellm-${resourceToken}'
    workloadProfileName: managedEnvironment.outputs.AZURE_RESOURCE_CONTAINER_APPS_WORKLOAD_PROFILE_NAME
    applicationInsightsConnectionString: appInsightsConnectionString
    definition: {
      settings: [
        {
          secret: true
          name: 'LITELLM_MASTER_KEY'
          keyVaultSecretName: 'litelLlmasterkey'
        }
        {
          secret: true
          name: 'AZURE_API_KEY'
          keyVaultSecretName: 'openaiapikey'
        }
        {
          name: 'AZURE_API_BASE'
          value: openAiApiBase
        }
        {
          name: 'PROXY_BASE_URL'
          value: litlLlmPublicFqdn ?? 'https://aca-litellm-${resourceToken}.${managedEnvironment.outputs.AZURE_RESOURCE_CONTAINER_APPS_ENVIRONMENT_DEFAULT_DOMAIN}'
        }
        {
          secret: true
          name: 'DATABASE_URL'
          keyVaultSecretName: postgressDb.outputs.pgConnectionStringSecretName
        }
      ]
    }
    containerArgs: [
      '--config'
      '/config/config.yml'
      '--port'
      '4000'
      // '--num_workers'
      // '2'
      '--detailed_debug'
    ]
    volumes: [
      {
        name: 'config'
        storageType: 'EmptyDir'
      }
    ]
    volumeMounts: [
      {
        volumeName: 'config'
        mountPath: '/config'
      }
    ]
    initContainersTemplate: [
      {
        name: 'config-initializer'
        image: 'busybox:latest'
        resources: {
          cpu: json('0.25')
          memory: '0.5Gi'
        }
        command: ['/bin/sh']
        args: [
          '-c'
          'printf "%s" "$CONFIG_YAML" > /config/config.yml && echo "Config file created:" && cat /config/config.yml'
        ]
        env: [
          {
            name: 'CONFIG_YAML'
            value: liteLlmConfigYaml
          }
        ]
        volumeMounts: [
          {
            volumeName: 'config'
            mountPath: '/config'
          }
        ]
      }
    ]
    ingressTargetPort: 4000
    existingImage: 'ghcr.io/berriai/litellm-database:main-stable'
    userAssignedManagedIdentityClientId: userAssignedIdentity.properties.clientId
    userAssignedManagedIdentityResourceId: userAssignedIdentity.id
    ingressExternal: true
    cpu: '0.25'
    memory: '0.5Gi'
    scaleMaxReplicas: 1
    scaleMinReplicas: 1
    containerAppsEnvironmentResourceId: managedEnvironment.outputs.AZURE_RESOURCE_CONTAINER_APPS_ENVIRONMENT_ID
    keyVaultName: keyVault.outputs.AZURE_RESOURCE_KEY_VAULT_NAME
    probes: [
      {
        type: 'Readiness'
        initialDelaySeconds: 5
        httpGet: {
          path: '/health/readiness'
          port: 4000
        }
      }
      {
        type: 'Liveness'
        initialDelaySeconds: 5
        httpGet: {
          path: '/health/liveliness'
          port: 4000
        }
      }
    ]
  }
}

module liteLlmConnection '../ai/connection-litellm-gateway.bicep' = {
  name: 'lite-llm-connection'
  params: {
    aiFoundryName: aiFoundryName
    connectionName: 'modelgateway-litellm-${resourceToken}'
    apiKey: litelLlmasterkey
    isSharedToAll: true
    gatewayName: 'litellm'
    targetUrl: liteLlmApp.outputs.AZURE_RESOURCE_CONTAINER_APP_FQDN
  }
}

output liteLlmAcaFqdn string = liteLlmApp.outputs.AZURE_RESOURCE_CONTAINER_APP_FQDN
