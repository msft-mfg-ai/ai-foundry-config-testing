param location string
param name string
param logAnalyticsWorkspaceResourceId string
param storages array
param publicNetworkAccess string
param infrastructureSubnetId string?
param appInsightsConnectionString string

// var workloadProfileName = 'default'
var workloadProfileName = 'Consumption'

var logAnalyticsWorkspaceParts = split(logAnalyticsWorkspaceResourceId, '/')
var logAnalyticsWorkspaceName = last(logAnalyticsWorkspaceParts)
var logAnalyticsResourceGroupName = logAnalyticsWorkspaceParts[length(logAnalyticsWorkspaceParts) - 5]
var logAnalyticsWorkspaceSubscriptionId = logAnalyticsWorkspaceParts[2]

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2025-07-01' existing = {
  name: logAnalyticsWorkspaceName
  scope: resourceGroup(logAnalyticsWorkspaceSubscriptionId, logAnalyticsResourceGroupName)
}

// Container apps environment
module containerAppsEnvironment 'br/public:avm/res/app/managed-environment:0.11.3' = {
  name: 'container-apps-environment'
  params: {
    name: name
    location: location
    zoneRedundant: false
    storages: storages
    publicNetworkAccess: publicNetworkAccess
    infrastructureSubnetResourceId: infrastructureSubnetId
    workloadProfiles: [
      {
        name: 'Consumption'
        workloadProfileType: 'Consumption'
        // minimumCount: 1
        // maximumCount: 1
      }
    ]
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalyticsWorkspace.properties.customerId
        sharedKey: logAnalyticsWorkspace.listKeys().primarySharedKey
      }
    }
    appInsightsConnectionString: appInsightsConnectionString
    openTelemetryConfiguration:{
      tracesConfiguration: {
        destinations: ['appInsights']
      }
      logsConfiguration: {
        destinations: ['appInsights']
      }
    }
  }
}

output AZURE_RESOURCE_CONTAINER_APPS_ENVIRONMENT_ID string = containerAppsEnvironment.outputs.resourceId
output AZURE_RESOURCE_CONTAINER_APPS_WORKLOAD_PROFILE_NAME string = workloadProfileName
output AZURE_RESOURCE_CONTAINER_APPS_WORKLOAD_PROFILE_CONSUMPTION string = 'Consumption'
output AZURE_RESOURCE_CONTAINER_APPS_ENVIRONMENT_NAME string = containerAppsEnvironment.outputs.name
