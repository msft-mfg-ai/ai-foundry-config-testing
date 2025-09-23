param principalId string

module roleAssignmentNetworkConnectionApprover 'br/public:avm/res/authorization/role-assignment/rg-scope:0.1.0' = {
  name: 'roleAssignmentNetworkConnectionApproverDeployment'
  params: {
    // Required parameters
    principalId: principalId
    // roleDefinitionIdOrName: 'Azure AI Enterprise Network Connection Approver'
    roleDefinitionIdOrName: '/providers/Microsoft.Authorization/roleDefinitions/b556d68e-0be0-4f35-a333-ad7ee1ce17ea'
    // Non-required parameters
    principalType: 'ServicePrincipal'
  }
}

module roleAssignmentReader 'br/public:avm/res/authorization/role-assignment/rg-scope:0.1.0' = {
  name: 'roleAssignmentReaderDeployment'
  params: {
    // Required parameters
    principalId: principalId
    roleDefinitionIdOrName: 'Reader'
    // Non-required parameters
    principalType: 'ServicePrincipal'
  }
}
