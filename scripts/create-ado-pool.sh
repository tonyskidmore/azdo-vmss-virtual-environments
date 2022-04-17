#!/bin/bash

set -e

# define variables
script_path=$(dirname "$(realpath "$0")")
export script_path
echo "script_path: $script_path"
root_path=$(dirname "$script_path")
export root_path
echo "root_path: $root_path"

# export ADO_TOKEN=
# export ADO_ORG=
# export ADO_PROJECT=
# export ADO_SERVICE_CONNECTION=

project_json=$(curl -s -u ":$ADO_TOKEN" "https://dev.azure.com/$ADO_ORG/_apis/projects?api-version=7.1-preview.1")

project_count=$(echo "$project_json" | jq '.count')

echo "Found $project_count projects"

# https://phpfog.com/using-variables-in-jq-command-line-json-parser/
# project=$(echo "$project_json" | jq '.value | map(select(.name==env.ADO_PROJECT))')
project=$(echo "$project_json" | jq '.value | .[] | select(.name==env.ADO_PROJECT)')
echo "$project"

# .value | .[] | select(.name=="vmss") | .id
project_id=$(echo "$project" | jq -r '.id')

echo "id for project $ADO_PROJECT: $project_id"

# GET https://dev.azure.com/{organization}/{project}/_apis/serviceendpoint/endpoints?api-version=6.0-preview.4
# GET https://dev.azure.com/{organization}/{project}/_apis/serviceendpoint/endpoints?endpointNames={endpointNames}&api-version=6.0-preview.4

# url="https://dev.azure.com/$ADO_ORG/$ADO_PROJECT/_apis/serviceendpoint/endpoints?api-version=6.0-preview.4"
url="https://dev.azure.com/$ADO_ORG/$ADO_PROJECT/_apis/serviceendpoint/endpoints?endpointNames=$ADO_SERVICE_CONNECTION&api-version=6.0-preview.4"

endpoints=$(curl -s -u ":$ADO_TOKEN" "$url")
endpoint_id=$(echo "$endpoints" | jq -r '.value | .[].id')

echo "$endpoints" | jq
echo "endpoint_id: $endpoint_id"

# printf "***ENDPOINTS\n:%s" "$endpoints"

# GET https://dev.azure.com/{organization}/_apis/distributedtask/elasticpools?api-version=7.1-preview.1

elastic_pools=$(curl -s -u ":$ADO_TOKEN" "https://dev.azure.com/$ADO_ORG/_apis/distributedtask/elasticpools?api-version=7.1-preview.1")

echo "$elastic_pools"

pool_name="vmss"
authorize_all_pipelines="True"
auto_provision_project_pools="False"

# GET https://dev.azure.com/{organization}/{project}/_apis/serviceendpoint/endpoints?api-version=6.0-preview.4

# https://docs.microsoft.com/en-us/rest/api/azure/devops/distributedtask/elasticpools/create?view=azure-devops-rest-7.1
# POST https://dev.azure.com/{organization}/_apis/distributedtask/elasticpools?poolName={poolName}&authorizeAllPipelines={authorizeAllPipelines}&autoProvisionProjectPools={autoProvisionProjectPools}&projectId={projectId}&api-version=7.1-preview.1
url="https://dev.azure.com/$ADO_ORG/_apis/distributedtask/elasticpools?poolName=$pool_name&authorizeAllPipelines=$authorize_all_pipelines&autoProvisionProjectPools=$auto_provision_project_pools&projectId=$project_id&api-version=7.1-preview.1"

echo "$url"
# json_data='{}'

# new_pool=$(curl -s -X POST -H "Content-Type: application/json" -d "$json_data" -u ":$ADO_TOKEN" "$url" )

cd "$script_path"

# uncommment when service endpoint is available
echo "$PWD"
new_pool=$(curl -s -X POST -H "Content-Type: application/json" -d @params.json -u ":$ADO_TOKEN" "$url" )
echo "$new_pool" | jq
