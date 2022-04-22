#!/bin/bash

set -e

# define variables
script_path=$(dirname "$(realpath "$0")")
echo "script_path: $script_path"
root_path=$(dirname "$script_path")
echo "root_path: $root_path"

# functions

# shellcheck disable=SC1091
. "$script_path/bash_functions/array_contains"
# shellcheck disable=SC1091
. "$script_path/bash_functions/check_arm_env_vars"
# shellcheck disable=SC1091
. "$script_path/bash_functions/display_message"

# end functions

check_arm_env_vars

# Set defaults overridable by environment variables
export ADO_POOL_NAME=${ADO_POOL_NAME:-ve-vmss}
export ADO_POOL_AUTH_ALL=${ADO_POOL_AUTH_ALL:-True}
export ADO_POOL_AUTO_PROVISION=${ADO_POOL_AUTO_PROVISION:-False}
export ADO_PROJECT=${ADO_PROJECT:-ve-vmss}
export ADO_PROJECT_DESC=${ADO_PROJECT_DESC:-VMSS Agents}
export ADO_PROJECT_PROCESS=${ADO_PROJECT_PROCESS:-Basic}
export ADO_PROJECT_VISIBILITY=${ADO_PROJECT_VISIBILITY:-private}
export ADO_SERVICE_CONNECTION=${ADO_SERVICE_CONNECTION:-ve-vmss}
export AZ_VMSS_RESOURCE_GROUP_NAME=${AZ_VMSS_RESOURCE_GROUP_NAME:-rg-vmss-azdo-agents-01}
export AZ_VMSS_NAME=${AZ_VMSS_NAME:-vmss-azdo-agents-01}


if [[ -z $AZURE_DEVOPS_EXT_PAT || -z $ADO_ORG ]]
then
  echo "Required environment variables not set. Please set these values and re-run the script."
  echo "For example:"
  echo " export ADO_TOKEN=7xoaw8lo9vzwpaalfqf6d723i3lk88yslog4c42eby55ducploga"
  echo "export ADO_ORG=https://dev.azure.com/my-ado-org"
  # echo "export AZURE_VMSS_ID=/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-vmss-azdo-agents-01/providers/Microsoft.Compute/virtualMachineScaleSets/vmss-azdo-agents-01"
  echo "Note: The preceding space on the line above so that the command does not appear in command history"
  exit 1
fi

echo "ADO_POOL_NAME: $ADO_POOL_NAME"
echo "ADO_POOL_AUTH_ALL: $ADO_POOL_AUTH_ALL"
echo "ADO_POOL_AUTO_PROVISION: $ADO_POOL_AUTO_PROVISION"
echo "ADO_PROJECT: $ADO_PROJECT"
echo "ADO_PROJECT_VISIBILITY: $ADO_PROJECT_VISIBILITY"
echo "ADO_SERVICE_CONNECTION: $ADO_SERVICE_CONNECTION"
echo "AZ_VMSS_RESOURCE_GROUP_NAME: $AZ_VMSS_RESOURCE_GROUP_NAME"
echo "AZ_VMSS_NAME: $AZ_VMSS_NAME"

#TODO: make devops query function DRY
#TODO: handle if no projects are returned
display_message info "Get Azure DevOps current project list"
ado_project_list=$(az devops project list \
  --organization "$ADO_ORG" \
  --output json)

readarray -t ado_projects <<< "$(echo "$ado_project_list" | jq -r '.value[].name')"
declare -p ado_projects

if array_contains ado_projects "$ADO_PROJECT"
then
  display_message info "Azure DevOps project $ADO_PROJECT already exists"
else
  display_message info "Creating Azure DevOps project $ADO_PROJECT"
  az devops project create \
    --name "$ADO_PROJECT" \
    --organization "$ADO_ORG" \
    --description "$ADO_PROJECT_DESC" \
    --visibility "$ADO_PROJECT_VISIBILITY" \
    --process "$ADO_PROJECT_PROCESS"
fi

display_message info "Get Azure DevOps endpoint list"
ado_endpoint_list=$(az devops service-endpoint list \
  --project "$ADO_PROJECT" \
  --organization "$ADO_ORG" \
  --output json)

readarray -t ado_endpoints <<< "$(echo "$ado_endpoint_list" | jq -r '.[].name')"
declare -p ado_endpoints

# https://docs.microsoft.com/en-us/cli/azure/devops/service-endpoint/azurerm?view=azure-cli-latest#az-devops-service-endpoint-azurerm-create
export AZURE_DEVOPS_EXT_AZURE_RM_SERVICE_PRINCIPAL_KEY="$ARM_CLIENT_SECRET"

if array_contains ado_endpoints "$ADO_SERVICE_CONNECTION"
then
  display_message info "Azure DevOps service endpoint $ADO_SERVICE_CONNECTION already exists"
else
display_message info "Creating Azure DevOps service connection $ADO_SERVICE_CONNECTION"
az devops service-endpoint azurerm create \
  --azure-rm-service-principal-id "$ARM_CLIENT_ID" \
  --azure-rm-subscription-id "$ARM_SUBSCRIPTION_ID" \
  --azure-rm-subscription-name "VMSS Subscription" \
  --azure-rm-tenant-id "$ARM_TENANT_ID" \
  --name "$ADO_SERVICE_CONNECTION" \
  --project "$ADO_PROJECT" \
  --organization "$ADO_ORG"
fi

exit 0

######## original script
# https://docs.microsoft.com/en-us/rest/api/azure/devops/core/Projects/List?view=azure-devops-rest-7.1
url="https://dev.azure.com/$ADO_ORG/_apis/projects?api-version=7.1-preview.1"
project_json=$(curl -s -u ":$ADO_TOKEN" "$url")

project_count=$(echo "$project_json" | jq '.count')

display_message info "Found $project_count projects"

# get specific project details from the project list
project=$(echo "$project_json" | jq '.value | .[] | select(.name==env.ADO_PROJECT)')
display_message info "project: $project"


# project the ID will be used for elasticpool serviceEndpointScope
project_id=$(echo "$project" | jq -r '.id')
display_message info "id for project $ADO_PROJECT: $project_id"

# https://docs.microsoft.com/en-us/rest/api/azure/devops/serviceEndpoint/endpoints/get-service-endpoints-by-names?view=azure-devops-rest-7.1
url="https://dev.azure.com/$ADO_ORG/$ADO_PROJECT/_apis/serviceendpoint/endpoints?endpointNames=$ADO_SERVICE_CONNECTION&api-version=7.1-preview.4"
endpoints=$(curl -s -u ":$ADO_TOKEN" "$url")
endpoint_id=$(echo "$endpoints" | jq -r '.value | .[].id')
display_message info "endpoint_id: $endpoint_id"


# https://docs.microsoft.com/en-us/rest/api/azure/devops/distributedtask/elasticpools/list?view=azure-devops-rest-7.1
url="https://dev.azure.com/$ADO_ORG/_apis/distributedtask/elasticpools?api-version=7.1-preview.1"
elastic_pools=$(curl -s -u ":$ADO_TOKEN" "$url")
display_message info "existing elasticspools:"
echo "$elastic_pools"

# copy template and patch params.json with values
display_message info "Creating $script_path/params.json"
cp "$script_path/params.json.template" "$script_path/params.json"
sed -i "s|\"azureId\":.*|\"azureId\": \"$AZURE_VMSS_ID\",|" "$script_path/params.json"
sed -i "s|\"serviceEndpointId\":.*|\"serviceEndpointId\": \"$endpoint_id\",|" "$script_path/params.json"
sed -i "s|\"serviceEndpointScope\":.*|\"serviceEndpointScope\": \"$project_id\",|" "$script_path/params.json"
echo "$script_path/params.json"
cat "$script_path/params.json"

# https://docs.microsoft.com/en-us/rest/api/azure/devops/distributedtask/elasticpools/create?view=azure-devops-rest-7.1
# POST https://dev.azure.com/{organization}/_apis/distributedtask/elasticpools?poolName={poolName}&authorizeAllPipelines={authorizeAllPipelines}&autoProvisionProjectPools={autoProvisionProjectPools}&projectId={projectId}&api-version=7.1-preview.1
url="https://dev.azure.com/$ADO_ORG/_apis/distributedtask/elasticpools?poolName=$ADO_POOL_NAME&authorizeAllPipelines=$ADO_POOL_AUTH_ALL&autoProvisionProjectPools=$ADO_POOL_AUTO_PROVISION&projectId=$project_id&api-version=7.1-preview.1"
display_message info "Constructed elastic pool create url:"
echo "$url"

display_message info "Creating Azure DevOps pool: $ADO_POOL_NAME"
new_pool=$(curl -s -X POST -H "Content-Type: application/json" -d @"$script_path/params.json" -u ":$ADO_TOKEN" "$url" )
echo "$new_pool"
