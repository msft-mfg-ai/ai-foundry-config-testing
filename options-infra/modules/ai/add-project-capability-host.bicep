param cosmosDBConnection string = ''
param azureStorageConnection string = ''
param aiSearchConnection string = ''
param aiFoundryConnectionName string = ''
param projectName string
param accountName string
param projectCapHost string

var threadConnections = empty(cosmosDBConnection) ? [] : ['${cosmosDBConnection}']
var storageConnections = empty(azureStorageConnection) ? [] : ['${azureStorageConnection}']
var vectorStoreConnections = empty(aiSearchConnection) ? [] : ['${aiSearchConnection}']
var aiConnections = empty(aiFoundryConnectionName) ? [] : ['${aiFoundryConnectionName}']

var isStandardSetup = !empty(cosmosDBConnection) && !empty(azureStorageConnection) && !empty(aiSearchConnection)
var isCustomAiConnection = !empty(aiConnections)

resource account 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' existing = {
   name: accountName
}

resource project 'Microsoft.CognitiveServices/accounts/projects@2025-04-01-preview' existing = {
  name: projectName
  parent: account
}

resource projectCapabilityHostAgents 'Microsoft.CognitiveServices/accounts/projects/capabilityHosts@2025-04-01-preview' = if(!isStandardSetup && !isCustomAiConnection) {
  name: projectCapHost
  parent: project
  properties: {
    capabilityHostKind: 'Agents'
  }
}

resource projectCapabilityHostBasic 'Microsoft.CognitiveServices/accounts/projects/capabilityHosts@2025-04-01-preview' = if(!isStandardSetup && isCustomAiConnection) {
  name: projectCapHost
  parent: project
  properties: {
    capabilityHostKind: 'Agents'
    aiServicesConnections: aiConnections
  }
}

resource projectCapabilityHostStandard 'Microsoft.CognitiveServices/accounts/projects/capabilityHosts@2025-04-01-preview' = if(isStandardSetup && isCustomAiConnection) {
  name: projectCapHost
  parent: project
  properties: {
    capabilityHostKind: 'Agents'
    vectorStoreConnections: vectorStoreConnections
    storageConnections: storageConnections
    threadStorageConnections: threadConnections
    aiServicesConnections: aiConnections
  }
}
