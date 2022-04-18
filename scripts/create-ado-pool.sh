#!/bin/bash

set -e

# define variables
script_path=$(dirname "$(realpath "$0")")
echo "script_path: $script_path"
root_path=$(dirname "$script_path")
echo "root_path: $root_path"

if [[ -z $ADO_TOKEN || -z $ADO_ORG || -z $ADO_PROJECT || -z $ADO_SERVICE_CONNECTION || -z $AZURE_VMSS_ID ]]
then
  # AZURE_VMSS_ID is the resource ID of the target VMSS
  echo "Required environment variables not set. Please set these values and re-run the script."
  echo "For example:"
  echo " export ADO_TOKEN=7xoaw8lo9vzwpaalfqf6d723i3lk88yslog4c42eby55ducploga"
  echo "export ADO_ORG=my-ado-org"
  echo "export ADO_PROJECT=vmss"
  echo "export ADO_SERVICE_CONNECTION=vmss"
  echo "export AZURE_VMSS_ID=/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-vmss-azdo-agents-01/providers/Microsoft.Compute/virtualMachineScaleSets/vmss-azdo-agents-01"
  echo "Note: The preceding space on the line above so that the command does not appear in command history"
  exit 1
fi

# https://docs.microsoft.com/en-us/rest/api/azure/devops/core/Projects/List?view=azure-devops-rest-7.1
url="https://dev.azure.com/$ADO_ORG/_apis/projects?api-version=7.1-preview.1"
project_json=$(curl -s -u ":$ADO_TOKEN" "$url")

project_count=$(echo "$project_json" | jq '.count')

echo "Found $project_count projects"

# get specific project details from the project list
project=$(echo "$project_json" | jq '.value | .[] | select(.name==env.ADO_PROJECT)')
echo "$project"


# project the ID will be used for elasticpool serviceEndpointScope
project_id=$(echo "$project" | jq -r '.id')
echo "id for project $ADO_PROJECT: $project_id"

# https://docs.microsoft.com/en-us/rest/api/azure/devops/serviceEndpoint/endpoints/get-service-endpoints-by-names?view=azure-devops-rest-7.1
url="https://dev.azure.com/$ADO_ORG/$ADO_PROJECT/_apis/serviceendpoint/endpoints?endpointNames=$ADO_SERVICE_CONNECTION&api-version=7.1-preview.4"
endpoints=$(curl -s -u ":$ADO_TOKEN" "$url")
endpoint_id=$(echo "$endpoints" | jq -r '.value | .[].id')
echo "endpoint_id: $endpoint_id"


# https://docs.microsoft.com/en-us/rest/api/azure/devops/distributedtask/elasticpools/list?view=azure-devops-rest-7.1
url="https://dev.azure.com/$ADO_ORG/_apis/distributedtask/elasticpools?api-version=7.1-preview.1"
elastic_pools=$(curl -s -u ":$ADO_TOKEN" "$url")
echo "leasticspools:"
echo "$elastic_pools" | jq

pool_name="vmss"
authorize_all_pipelines="True"
auto_provision_project_pools="False"

# https://docs.microsoft.com/en-us/rest/api/azure/devops/distributedtask/elasticpools/create?view=azure-devops-rest-7.1
# POST https://dev.azure.com/{organization}/_apis/distributedtask/elasticpools?poolName={poolName}&authorizeAllPipelines={authorizeAllPipelines}&autoProvisionProjectPools={autoProvisionProjectPools}&projectId={projectId}&api-version=7.1-preview.1
url="https://dev.azure.com/$ADO_ORG/_apis/distributedtask/elasticpools?poolName=$pool_name&authorizeAllPipelines=$authorize_all_pipelines&autoProvisionProjectPools=$auto_provision_project_pools&projectId=$project_id&api-version=7.1-preview.1"
echo "$url"

cd "$script_path"

# patch params.json with values
sed -i "s|\"azureId\":.*|\"azureId\": \"$AZURE_VMSS_ID\",|" "$script_path/params.json"
sed -i "s|\"serviceEndpointId\":.*|\"serviceEndpointId\": \"$endpoint_id\",|" "$script_path/params.json"
sed -i "s|\"serviceEndpointScope\":.*|\"serviceEndpointScope\": \"$project_id\",|" "$script_path/params.json"
echo "$script_path/params.json"
cat "$script_path/params.json"

new_pool=$(curl -s -X POST -H "Content-Type: application/json" -d @"$script_path/params.json" -u ":$ADO_TOKEN" "$url" )
echo "$new_pool" | jq
