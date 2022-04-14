#!/bin/bash

# https://docs.microsoft.com/en-us/cli/azure/group?view=azure-cli-latest#az-group-create
az group create \
  --name "$AZ_NET_RESOURCE_GROUP_NAME" \
  --location "$AZ_LOCATION"

# https://docs.microsoft.com/en-us/cli/azure/network/vnet?view=azure-cli-latest#az-network-vnet-create
az network vnet create \
  --resource-group "$AZ_NET_RESOURCE_GROUP_NAME" \
  --name "$AZ_NET_NAME" \
  --address-prefix "$AZ_NET_ADR_PREFIXES"

# https://docs.microsoft.com/en-us/cli/azure/network/vnet/subnet?view=azure-cli-latest#az-network-vnet-subnet-create
az network vnet subnet create \
  --resource-group "$AZ_NET_RESOURCE_GROUP_NAME" \
  --vnet-name "$AZ_NET_NAME" \
  --name "$AZ_SUBNET_NAME" \
  --address-prefixes "$AZ_SUBNET_ADR_PREFIXES"

az group create \
  --name "$AZ_RESOURCE_GROUP_NAME" \
  --location "$AZ_LOCATION"
