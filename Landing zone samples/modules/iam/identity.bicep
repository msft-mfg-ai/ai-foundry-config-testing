// --------------------------------------------------------------------------------------------------------------
// Bicep file to deploy and identity
// --------------------------------------------------------------------------------------------------------------
// Test Deploy Command:
//   az deployment group create -n manual-identity --resource-group rg-ai-docs-114-dev --template-file 'core/iam/identity.bicep' --parameters existingIdentityName='llaz114-app-id'
// --------------------------------------------------------------------------------------------------------------
param identityName string = ''
param existingIdentityName string  = ''
param location string = resourceGroup().location
param tags object = {}

var useExistingIdentity = !empty(existingIdentityName)

resource existingIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-07-31-preview' existing = if (useExistingIdentity) {
  name: existingIdentityName
}

resource newIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-07-31-preview' = if (!useExistingIdentity) {
  name: identityName
  location: location
  tags: tags
}

// --------------------------------------------------------------------------------------------------------------
// Outputs
// --------------------------------------------------------------------------------------------------------------
output managedIdentityId string = useExistingIdentity ? existingIdentity.id : newIdentity.id
output managedIdentityName string = useExistingIdentity ? existingIdentity.name : newIdentity.name
output managedIdentityClientId string = useExistingIdentity ? existingIdentity.properties.clientId : newIdentity.properties.clientId
output managedIdentityPrincipalId string = useExistingIdentity ? existingIdentity.properties.principalId : newIdentity.properties.principalId
