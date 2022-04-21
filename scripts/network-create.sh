#!/bin/bash

# Simple script to create a network and a subnet

set -e

# define variables
script_path=$(dirname "$(realpath "$0")")
export script_path
echo "script_path: $script_path"
root_path=$(dirname "$script_path")
export root_path
echo "root_path: $root_path"

# functions

# shellcheck disable=SC1091
. "$script_path/bash_functions/check_arm_env_vars"
# shellcheck disable=SC1091
. "$script_path/bash_functions/display_message"

# end functions

export AZ_NET_RESOURCE_GROUP_NAME="${AZ_NET_RESOURCE_GROUP_NAME:-rg-azdo-agents-networks-01}"
export AZ_NET_NAME="${AZ_NET_NAME:-vnet-azdo-agents-01}"
export AZ_NET_ADR_PREFIXES="${AZ_NET_ADR_PREFIXES:-172.16.0.0/12}"
export AZ_SUBNET_NAME="${AZ_SUBNET_NAME:-snet-azdo-agents-01}"
export AZ_SUBNET_ADR_PREFIXES="${AZ_SUBNET_ADR_PREFIXES:-172.16.0.0/24}"
export AZ_LOCATION="${AZ_LOCATION:-uksouth}"

echo "AZ_NET_RESOURCE_GROUP_NAME: ${AZ_NET_RESOURCE_GROUP_NAME}"
echo "AZ_NET_NAME: ${AZ_NET_NAME}"
echo "AZ_NET_ADR_PREFIXES: ${AZ_NET_ADR_PREFIXES}"
echo "AZ_SUBNET_NAME: ${AZ_SUBNET_NAME}"
echo "AZ_SUBNET_ADR_PREFIXES: ${AZ_SUBNET_ADR_PREFIXES}"
echo "AZ_LOCATION: ${AZ_LOCATION}"

check_arm_env_vars

display_message info "Logging into Azure..."
az login --service-principal -u "$ARM_CLIENT_ID" -p "$ARM_CLIENT_SECRET" --tenant "$ARM_TENANT_ID"
az account set --subscription "$ARM_SUBSCRIPTION_ID"

# https://docs.microsoft.com/en-us/cli/azure/group?view=azure-cli-latest#az-group-create
display_message info "Creating resource group $AZ_NET_RESOURCE_GROUP_NAME"
az group create \
  --name "$AZ_NET_RESOURCE_GROUP_NAME" \
  --location "$AZ_LOCATION"

vnet_query=("network" "vnet" "list" \
            "--resource-group" "$AZ_NET_RESOURCE_GROUP_NAME" \
            "--output" "json")

display_message info "Running: az ${vnet_query[*]}"
vnet_result="$(az "${vnet_query[@]}")"
vnet_query_name=$(echo "$vnet_result" | jq -r '.[].name')
display_message info "vnet query found:"
printf "%s\n" "$vnet_query_name"

if [[ "$vnet_query_name" != "$AZ_NET_NAME" ]]
then
  display_message info "Creating network: $AZ_NET_NAME"
  # https://docs.microsoft.com/en-us/cli/azure/network/vnet?view=azure-cli-latest#az-network-vnet-create
  az network vnet create \
    --resource-group "$AZ_NET_RESOURCE_GROUP_NAME" \
    --name "$AZ_NET_NAME" \
    --address-prefix "$AZ_NET_ADR_PREFIXES"
else
  display_message warning "Network already exists: $AZ_NET_NAME"
fi

subnet_query=("network" "vnet" "subnet" "list" \
              "--vnet-name" "$AZ_NET_NAME" \
              "--resource-group" "$AZ_NET_RESOURCE_GROUP_NAME" \
              "--output" "json")

display_message info "Running: az ${subnet_query[*]}"
subnet_result="$(az "${subnet_query[@]}")"
subnet_query_name=$(echo "$subnet_result" | jq -r '.[].name')
display_message info "subnet query found:"
printf "%s\n" "$subnet_query_name"

if [[ "$subnet_query_name" != "$AZ_SUBNET_NAME" ]]
then
  # https://docs.microsoft.com/en-us/cli/azure/network/vnet/subnet?view=azure-cli-latest#az-network-vnet-subnet-create
  display_message info "Creating subnet $AZ_SUBNET_NAME"
  az network vnet subnet create \
    --resource-group "$AZ_NET_RESOURCE_GROUP_NAME" \
    --vnet-name "$AZ_NET_NAME" \
    --name "$AZ_SUBNET_NAME" \
    --address-prefixes "$AZ_SUBNET_ADR_PREFIXES"
else
  display_message warning "Subnet already exists: $AZ_SUBNET_NAME"
fi
