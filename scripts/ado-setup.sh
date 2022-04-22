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
export ADO_REPO=${ADO_REPO:-ve-vmss}
export ADO_REPO_SOURCE=${ADO_REPO_SOURCE:-https://github.com/tonyskidmore/azdo-vmss-virtual-environments}
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
echo "ADO_PROJECT_DESC: $ADO_PROJECT_DESC"
echo "ADO_PROJECT_PROCESS: $ADO_PROJECT_PROCESS"
echo "ADO_PROJECT_VISIBILITY: $ADO_PROJECT_VISIBILITY"
echo "ADO_SERVICE_CONNECTION: $ADO_SERVICE_CONNECTION"
echo "ADO_REPO: $ADO_REPO"
echo "ADO_REPO_SOURCE: $ADO_REPO_SOURCE"
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
  ado_azurerm_sc=$(az devops service-endpoint azurerm create \
    --azure-rm-service-principal-id "$ARM_CLIENT_ID" \
    --azure-rm-subscription-id "$ARM_SUBSCRIPTION_ID" \
    --azure-rm-subscription-name "VMSS Subscription" \
    --azure-rm-tenant-id "$ARM_TENANT_ID" \
    --name "$ADO_SERVICE_CONNECTION" \
    --project "$ADO_PROJECT" \
    --organization "$ADO_ORG" \
    --output json)

  # https://docs.microsoft.com/en-us/cli/azure/devops/service-endpoint?view=azure-cli-latest#ext_azure_devops_az_devops_service_endpoint_update-optional-parameters
  az devops service-endpoint update \
    --id "$(echo "$ado_azurerm_sc" | jq -r '.id')" \
    --enable-for-all \
    --project "$ADO_PROJECT" \
    --organization "$ADO_ORG"
fi



display_message info "Get Azure DevOps repo list"
ado_repo_list=$(az repos list \
  --project "$ADO_PROJECT" \
  --organization "$ADO_ORG" \
  --output json)

readarray -t ado_repos <<< "$(echo "$ado_repo_list" | jq -r '.[].name')"
declare -p ado_repos

if array_contains ado_repos "$ADO_REPO"
then
  display_message info "Azure DevOps repo $ADO_REPO already exists"
else
  display_message info "Creating Azure DevOps repo $ADO_REPO"
  az repos create \
    --name "$ADO_REPO" \
    --project "$ADO_PROJECT" \
    --organization "$ADO_ORG"
fi

# conditionally run import depending on whether files already exist in the repo
display_message info "Get items from Azure DevOps repo $ADO_REPO"
repo_id=$(az repos show --repository "$ADO_REPO" --project "$ADO_PROJECT" --organization "$ADO_ORG" --query 'id' --output tsv)
url="$ADO_ORG/_apis/git/repositories/$repo_id/items?scopePath=/scripts&recursionLevel=Full&includeContentMetadata=true&api-version=7.1-preview.1"
items=$(curl -s -u ":$AZURE_DEVOPS_EXT_PAT" "$url" )
count=$(echo "$items" | jq -r '.count')

if [[ $count -gt 0 ]]
then
  display_message info "$ADO_REPO is not empty, not attempting to import"
else
  display_message info "Import repo $ADO_REPO_SOURCE into $ADO_REPO"
  az repos import create --git-source-url "$ADO_REPO_SOURCE" \
    --project "$ADO_PROJECT" \
    --organization "$ADO_ORG" \
    --repository "$ADO_REPO"
fi

display_message info "Get Azure DevOps pool list"
ado_pool_list=$(az pipelines pool list \
  --organization "$ADO_ORG" \
  --output json)

display_message info "Get Azure DevOps endpoint list"
ado_endpoint_list=$(az devops service-endpoint list \
  --project "$ADO_PROJECT" \
  --organization "$ADO_ORG" \
  --output json)

project_id=$(az devops project show --project "$ADO_PROJECT" --org "$ADO_ORG" --query 'id' --output tsv)
endpoint_id=$(echo "$ado_endpoint_list" | jq -r --arg name "$ADO_SERVICE_CONNECTION" '.[] | select (.name==$name) | .id')
pool_id=$(echo "$ado_pool_list" | jq -r --arg name "$ADO_POOL_NAME" '.[] | select (.name==$name) | .id')

display_message info "Obtained IDs"
printf "project_id: %s\n" "$project_id"
printf "endpoint_id: %s\n" "$endpoint_id"
printf "pool_id: %s\n" "$pool_id"

if [[ -z "$pool_id" ]]
then

  # login to Azure and get the VMSS ID
  display_message info "Logging into Azure..."
  az login --service-principal -u "$ARM_CLIENT_ID" -p "$ARM_CLIENT_SECRET" --tenant "$ARM_TENANT_ID"
  az account set --subscription "$ARM_SUBSCRIPTION_ID"

  display_message info "Getting VMSS ID"
  az_vmss_id=$(az vmss show \
    --resource-group "$AZ_VMSS_RESOURCE_GROUP_NAME" \
    --name "$AZ_VMSS_NAME" \
    --query 'id' \
    --output tsv)

  printf "az_vmss_id: %s\n" "$az_vmss_id"

  display_message info "Creating Azure DevOps pool $ADO_POOL_NAME"
  # copy template and patch params.json with values
  display_message info "Creating $script_path/params.json"
  cp "$script_path/params.json.template" "$script_path/params.json"
  sed -i "s|\"azureId\":.*|\"azureId\": \"$az_vmss_id\",|" "$script_path/params.json"
  sed -i "s|\"serviceEndpointId\":.*|\"serviceEndpointId\": \"$endpoint_id\",|" "$script_path/params.json"
  sed -i "s|\"serviceEndpointScope\":.*|\"serviceEndpointScope\": \"$project_id\",|" "$script_path/params.json"
  echo "$script_path/params.json"
  cat "$script_path/params.json"

  # https://docs.microsoft.com/en-us/rest/api/azure/devops/distributedtask/elasticpools/create?view=azure-devops-rest-7.1
  # POST https://dev.azure.com/{organization}/_apis/distributedtask/elasticpools?poolName={poolName}&authorizeAllPipelines={authorizeAllPipelines}&autoProvisionProjectPools={autoProvisionProjectPools}&projectId={projectId}&api-version=7.1-preview.1
  url="$ADO_ORG/_apis/distributedtask/elasticpools?poolName=$ADO_POOL_NAME&authorizeAllPipelines=$ADO_POOL_AUTH_ALL&autoProvisionProjectPools=$ADO_POOL_AUTO_PROVISION&projectId=$project_id&api-version=7.1-preview.1"
  display_message info "Constructed elastic pool create url:"
  echo "$url"

  display_message info "Creating Azure DevOps pool: $ADO_POOL_NAME"
  new_pool=$(curl -s -X POST -H "Content-Type: application/json" -d @"$script_path/params.json" -u ":$AZURE_DEVOPS_EXT_PAT" "$url" )
  echo "$new_pool"
else
  display_message info "Azure DevOps pool $ADO_POOL_NAME already exists"
fi

display_message info "Get Azure DevOps pipelines list"
ado_pipeline_list=$(az pipelines list \
  --project "$ADO_PROJECT" \
  --organization "$ADO_ORG" \
  --output json)

readarray -t ado_pipelines <<< "$(echo "$ado_pipeline_list" | jq -r '.[].name')"
declare -p ado_pipelines

declare -A pipelines
pipelines["vmss-test"]="/.pipelines/vmss-test.yml"
pipelines["image-build"]="/.pipelines/image-build.yml"
pipelines["terraform-example"]="/.pipelines/terraform-example.yml"

for pipeline in "${!pipelines[@]}"
do
  if array_contains ado_pipelines "$pipeline"
  then
    display_message info "Azure DevOps pipeline $pipeline already exists"
  else
    display_message info "Creating Azure DevOps pipeline $pipeline"
    az pipelines create \
      --name "$pipeline" \
      --project "$ADO_PROJECT" \
      --organization "$ADO_ORG" \
      --yml-path ${pipelines[${pipeline}]} \
      --organization "$ADO_ORG" \
      --repository "$ADO_REPO" \
      --repository-type tfsgit \
      --skip-first-run true
  fi
done
