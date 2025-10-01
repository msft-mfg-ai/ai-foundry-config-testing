param newLogAnalyticsName string = ''
param newApplicationInsightsName string = ''

param existingLogAnalyticsName string = ''
param existingLogAnalyticsRgName string = ''
param existingApplicationInsightsName string = ''
param managedIdentityId string = ''

param location string = resourceGroup().location
param tags object = {}
param azureMonitorPrivateLinkScopeName string = ''
param azureMonitorPrivateLinkScopeResourceGroupName string = ''
param privateEndpointSubnetId string = ''
param privateEndpointName string = ''
param publicNetworkAccessForIngestion string = 'Enabled'
param publicNetworkAccessForQuery string = 'Enabled'

var useExistingLogAnalytics = !empty(existingLogAnalyticsName)
var useExistingAppInsights = !empty(existingApplicationInsightsName)

var monitoringMetricsPublisherId = '3913510d-42f4-4e42-8a64-420c390055eb'

// --------------------------------------------------------------------------------------------------------------
// split managed identity resource ID to get the name
var identityParts = split(managedIdentityId, '/')
// get the name of the managed identity
var managedIdentityName = length(identityParts) > 0 ? identityParts[length(identityParts) - 1] : ''

resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-07-31-preview' existing = if (!empty(managedIdentityId)) {
  name: managedIdentityName
}

// -------------------------------------------------------
resource existingLogAnalyticsResource 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = if (useExistingLogAnalytics) {
  name: existingLogAnalyticsName
  scope: resourceGroup(existingLogAnalyticsRgName)
}

resource existingApplicationInsightsResource 'Microsoft.Insights/components@2020-02-02' existing = if (useExistingAppInsights) {
  name: existingApplicationInsightsName
}

resource newLogAnalyticsResource 'Microsoft.OperationalInsights/workspaces@2023-09-01' = if (!useExistingLogAnalytics) {
  name: newLogAnalyticsName
  location: location
  tags: tags
  properties: any({
    retentionInDays: 30
    features: {
      searchVersion: 1
    }
    sku: {
      name: 'PerGB2018'
    }
    publicNetworkAccessForIngestion: publicNetworkAccessForIngestion
    publicNetworkAccessForQuery: publicNetworkAccessForQuery
  })
}

resource newApplicationInsightsResource 'Microsoft.Insights/components@2020-02-02' = if (!useExistingAppInsights) {
  name: newApplicationInsightsName
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: newLogAnalyticsResource.id
    publicNetworkAccessForIngestion: publicNetworkAccessForIngestion
    publicNetworkAccessForQuery: publicNetworkAccessForQuery
    DisableLocalAuth: true
  }
}

resource azureMonitorPrivateLinkScope 'Microsoft.Insights/privateLinkScopes@2021-07-01-preview' existing = if (!empty(azureMonitorPrivateLinkScopeName)) {
  name: azureMonitorPrivateLinkScopeName
  scope: resourceGroup(azureMonitorPrivateLinkScopeResourceGroupName)
}

module azureMonitorPrivateLinkScopePrivateEndpoint '../networking/private-endpoint.bicep' = if (!empty(privateEndpointSubnetId)) {
  name: 'azure-monitor-private-link-scope-private-endpoint'
  params: {
    privateEndpointName: privateEndpointName
    groupIds: ['azuremonitor']
    targetResourceId: azureMonitorPrivateLinkScope.id
    subnetId: privateEndpointSubnetId
  }
}
 
resource roleAssignmentAppInsights 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(managedIdentityId) && useExistingAppInsights) {
  name: guid(subscription().id, existingApplicationInsightsResource.id, identity.id, 'Monitoring Metrics Publisher')
  scope: existingApplicationInsightsResource
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', monitoringMetricsPublisherId)
    principalId: identity!.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource roleAssignmentAppInsightsNew 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(managedIdentityId) && !useExistingAppInsights) {
  name: guid(subscription().id, newApplicationInsightsResource.id, identity.id, 'Monitoring Metrics Publisher')
  scope: newApplicationInsightsResource
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', monitoringMetricsPublisherId)
    principalId: identity!.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

output applicationInsightsId string = useExistingAppInsights
  ? existingApplicationInsightsResource.id
  : newApplicationInsightsResource.id
output applicationInsightsName string = useExistingAppInsights
  ? existingApplicationInsightsResource.name
  : newApplicationInsightsResource.name
output logAnalyticsWorkspaceId string = useExistingLogAnalytics
  ? existingLogAnalyticsResource.id
  : newLogAnalyticsResource.id
output logAnalyticsWorkspaceName string = useExistingLogAnalytics
  ? existingLogAnalyticsResource.name
  : newLogAnalyticsResource.name
output appInsightsConnectionString string = useExistingAppInsights
  ? existingApplicationInsightsResource.?properties.ConnectionString ?? ''
  : newApplicationInsightsResource.?properties.ConnectionString ?? ''
