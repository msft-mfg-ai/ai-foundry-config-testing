using 'main.bicep'

// Parameters for the main Bicep template
param existingAISearchId = readEnvironmentVariable('EXISTING_AI_SEARCH_ID', '')
param existingStorageId = readEnvironmentVariable('EXISTING_STORAGE_ID', '')
param existingCosmosDBId = readEnvironmentVariable('EXISTING_COSMOS_ID', '')
param foundryName = readEnvironmentVariable('FOUNDRY_NAME', '')
