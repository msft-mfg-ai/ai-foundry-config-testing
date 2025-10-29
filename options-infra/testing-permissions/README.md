# Testing permissions for projects and Foundry

## Step 1

```yaml
var roleAssignments types.FoundryRoleAssignmentsType = {
  foundry: [
  ]
  project: [
    'Azure AI User'
  ]
  aiServices: [
  ]
  storage: [
  ]
  aiSearch: [
  ]
}
```
Resulted in error - Parent resource: Failed to find parent name (AI Foundry)

![AI User Permission](step1-just-AI-User.png)