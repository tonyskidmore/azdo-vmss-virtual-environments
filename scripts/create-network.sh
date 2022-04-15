#!/bin/bash

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

# end functions

check_arm_env_vars

export AZ_NET_RESOURCE_GROUP_NAME="${AZ_NET_RESOURCE_GROUP_NAME:-rg-networks-01}"
export AZ_NET_NAME="${AZ_NET_NAME:-vnet-network-01}"
export AZ_NET_ADR_PREFIXES="${AZ_NET_ADR_PREFIXES:-172.16.0.0/12}"
export AZ_SUBNET_NAME="${AZ_SUBNET_NAME:-sub-azdo-agents-01}"
export AZ_SUBNET_ADR_PREFIXES="${AZ_SUBNET_ADR_PREFIXES:-172.16.0.0/24}"
export AZ_LOCATION="${AZ_LOCATION:-uksouth}"

echo "AZ_NET_RESOURCE_GROUP_NAME: ${AZ_NET_RESOURCE_GROUP_NAME}"
echo "AZ_NET_NAME: ${AZ_NET_NAME}"
echo "AZ_NET_ADR_PREFIXES: ${AZ_NET_ADR_PREFIXES}"
echo "AZ_SUBNET_NAME: ${AZ_SUBNET_NAME}"
echo "AZ_SUBNET_ADR_PREFIXES: ${AZ_SUBNET_ADR_PREFIXES}"
echo "AZ_LOCATION: ${AZ_LOCATION}"

# https://docs.microsoft.com/en-us/cli/azure/group?view=azure-cli-latest#az-group-create
echo "Creating resource group $AZ_NET_RESOURCE_GROUP_NAME"
az group create \
  --name "$AZ_NET_RESOURCE_GROUP_NAME" \
  --location "$AZ_LOCATION"

# TODO: this is not idempotent
# https://docs.microsoft.com/en-us/cli/azure/network/vnet?view=azure-cli-latest#az-network-vnet-create

vnet_query=("network" "vnet" "list" \
                    "--query" "[?name == '$AZ_NET_NAME'] | length(@)")

printf "Running: az %s\n" "${vnet_query[*]}"
vnet_result=$(az "${vnet_query[@]}")
exit_code=$?

printf "Number of Vnets matching name $AZ_NET_NAME: %s\n" "$vnet_result"

if [[ "$vnet_result" == "0" ]]
then
  echo "Creating network: $AZ_NET_NAME"
  az network vnet create \
    --resource-group "$AZ_NET_RESOURCE_GROUP_NAME" \
    --name "$AZ_NET_NAME" \
    --address-prefix "$AZ_NET_ADR_PREFIXES"
else
  echo "Network already exists: $AZ_NET_NAME"
fi

# https://docs.microsoft.com/en-us/cli/azure/network/vnet/subnet?view=azure-cli-latest#az-network-vnet-subnet-create
echo "Creating subnet $AZ_SUBNET_NAME"
az network vnet subnet create \
  --resource-group "$AZ_NET_RESOURCE_GROUP_NAME" \
  --vnet-name "$AZ_NET_NAME" \
  --name "$AZ_SUBNET_NAME" \
  --address-prefixes "$AZ_SUBNET_ADR_PREFIXES"
