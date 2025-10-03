targetScope = 'subscription'

param resourceGroupName string
param location string
param tags object

resource rg 'Microsoft.Resources/resourceGroups@2025-04-01' = {
  name: resourceGroupName
  location: location
  tags: tags
}
