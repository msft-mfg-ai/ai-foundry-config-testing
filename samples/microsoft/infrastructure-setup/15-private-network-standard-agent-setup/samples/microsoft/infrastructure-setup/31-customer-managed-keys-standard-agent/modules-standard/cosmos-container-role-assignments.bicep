// Assigns the necessary roles to the AI project

@description('Name of the AI Search resource')
param cosmosAccountName string

@description('Project name')
param projectPrincipalId string

param projectId string

var userThreadName = '${projectId}-thread-message-store'
var systemThreadName = '${projectId}-system-thread-message-store'
var entityStoreName = '${projectId}-agent-entity-store'


resource cosmosAccount 'Microsoft.DocumentDB/databaseAccounts@2024-12-01-preview' existing = {
  name: cosmosAccountName
  scope: resourceGroup()
}

// Reference existing database
resource database 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2024-12-01-preview' existing = {
  parent: cosmosAccount
  name: 'enterprise_memory'
}

resource containerUserMessageStore  'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2024-12-01-preview' existing = {
  parent: database
  name: userThreadName
}

#disable-next-line BCP081
resource containerSystemMessageStore 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2024-12-01-preview' existing = {
  parent: database
  name: systemThreadName
}

#disable-next-line BCP081
resource containerEntityStore 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2024-12-01-preview' existing = {
  parent: database
  name: entityStoreName
}


var roleDefinitionId = resourceId(
  'Microsoft.DocumentDB/databaseAccounts/sqlRoleDefinitions', 
  cosmosAccountName, 
  '00000000-0000-0000-0000-000000000002'
)

var scopeSystemContainer = '/subscriptions/${subscription().subscriptionId}/resourceGroups/${resourceGroup().name}/providers/Microsoft.DocumentDB/databaseAccounts/${cosmosAccountName}/dbs/enterprise_memory/colls/${systemThreadName}'
var scopeUserContainer = '/subscriptions/${subscription().subscriptionId}/resourceGroups/${resourceGroup().name}/providers/Microsoft.DocumentDB/databaseAccounts/${cosmosAccountName}/dbs/enterprise_memory/colls/${userThreadName}'
var scopeEntityContainer = '/subscriptions/${subscription().subscriptionId}/resourceGroups/${resourceGroup().name}/providers/Microsoft.DocumentDB/databaseAccounts/${cosmosAccountName}/dbs/enterprise_memory/colls/${entityStoreName}'

resource containerRoleAssignmentUserContainer 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2022-05-15' = {
  parent: cosmosAccount
  name: guid(projectId, containerUserMessageStore.id, roleDefinitionId, projectPrincipalId)
  properties: {
    principalId: projectPrincipalId
    roleDefinitionId: roleDefinitionId
    scope: scopeUserContainer
  }
  dependsOn: [
    containerUserMessageStore
  ]
}

resource containerRoleAssignmentSystemContainer 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2022-05-15' = {
  parent: cosmosAccount
  name: guid(projectId, containerSystemMessageStore.id, roleDefinitionId, projectPrincipalId)
  properties: {
    principalId: projectPrincipalId
    roleDefinitionId: roleDefinitionId
    scope: scopeSystemContainer
  }
  dependsOn: [
    containerSystemMessageStore
  ]
}
  
  resource containerRoleAssignmentEntityContainer 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2022-05-15' = {
    parent: cosmosAccount
    name: guid(projectId, containerEntityStore.id, roleDefinitionId, projectPrincipalId)
    properties: {
      principalId: projectPrincipalId
      roleDefinitionId: roleDefinitionId
      scope: scopeEntityContainer
    }
    dependsOn: [
      containerEntityStore
    ]
  }
