#!/bin/bash

set -e

# https://github.com/actions/virtual-environments/blob/main/docs/create-image-and-azure-resources.md#service-principal
if [[ -z $ARM_SUBSCRIPTION_ID || -z $ARM_TENANT_ID || -z $ARM_CLIENT_ID || -z $ARM_CLIENT_SECRET ]]; then
  echo "Azure environment variables not set. Please set these values and re-run the script."
  echo "This should be the values from a Service Principal with Contributor rights to the target subscription e.g.:"
  echo 'az ad sp create-for-rbac -n "sp-virtual-environments-images" --role Contributor --scopes /subscriptions/00000000-0000-0000-0000-000000000000'
  echo "{"
  echo "  appId": "00000000-0000-0000-0000-000000000000",
  echo "  displayName": "sp-virtual-enviroments-images",
  echo "  password": "AAABjkwhs7862782626_BsGGjkskj_MaGv",
  echo "  tenant": "00000000-0000-0000-0000-000000000000"
  echo "}"
  echo ""
  echo " export ARM_SUBSCRIPTION_ID=00000000-0000-0000-0000-000000000000"
  echo " export ARM_TENANT_ID=00000000-0000-0000-0000-000000000000"
  echo " export ARM_CLIENT_ID=00000000-0000-0000-0000-000000000000"
  echo " export ARM_CLIENT_SECRET=AAABjkwhs7862782626_BsGGjkskj_MaGv"
  echo "Note: The preceding space on each line above so that the command does not appear in command history"
  exit 1
fi

# define variables
script_path=$(dirname "$(realpath "$0")")
export script_path
echo "$script_path"
root_path=$(dirname "$script_path")
export root_path
echo "$root_path"

# Set defaults overridable by environment variables
export AZ_RESOURCE_GROUP_NAME="${AZ_RESOURCE_GROUP_NAME:-rg-ve-images}"
export AZ_LOCATION=${AZ_LOCATION:-uksouth}
export AZ_ACG_RESOURCE_GROUP_NAME=${AZ_ACG_RESOURCE_GROUP_NAME:-rg-ve-sig-01}
export AZ_ACG_NAME=${AZ_ACG_NAME:-sig_01}
export VE_IMAGE_PUBLISHER=${VE_IMAGE_PUBLISHER:-actions}
export VE_IMAGE_OFFER=${VE_IMAGE_OFFER:-virtual-environments}
export VE_IMAGE_SKU=${VE_IMAGE_SKU:-Ubuntu2004}
export VE_IMAGE_TYPE=${VE_IMAGE_TYPE:-Ubuntu2004}
export VE_RELEASE=${VE_RELEASE:-ubuntu20/20220405.4}
export PACKER_LOG=${PACKER_LOG:-1}
export PACKER_LOG_PATH=${PACKER_LOG_PATH:-$root_path/packer-log.txt}

echo "AZ_RESOURCE_GROUP_NAME=${AZ_RESOURCE_GROUP_NAME}"
echo "AZ_LOCATION=${AZ_LOCATION}"
echo "AZ_ACG_RESOURCE_GROUP_NAME=${AZ_ACG_RESOURCE_GROUP_NAME}"
echo "AZ_ACG_NAME=${AZ_ACG_NAME}"
echo "VE_IMAGE_PUBLISHER=${VE_IMAGE_PUBLISHER}"
echo "VE_IMAGE_OFFER=${VE_IMAGE_OFFER}"
echo "VE_IMAGE_SKU=${VE_IMAGE_SKU}"
echo "VE_IMAGE_TYPE=${VE_IMAGE_TYPE}"
echo "VE_RELEASE=${VE_RELEASE:-ubuntu20/20220405.4}"
echo "PACKER_LOG=${PACKER_LOG}"
echo "PACKER_LOG_PATH=${PACKER_LOG_PATH}"

if [[ -d "$root_path/virtual-environments" ]] && [[ -n "$root_path" ]]
then
  echo "removing existing $root_path/virtual-environments directory"
  rm -rf "$root_path/virtual-environments"
fi

git clone -b "$VE_RELEASE" --single-branch https://github.com/actions/virtual-environments.git "$root_path/virtual-environments"

pwsh -File "$script_path/create-ve-image.ps1"

# get required outputs from packer log file
ostype=$(grep -Po '^OSType:\s\K([a-zA-Z]+)$' "$PACKER_LOG_PATH/packer-log.txt")
osdiskuri=$(grep -Po '^OSDiskUri:\s\K(.+)$' "$PACKER_LOG_PATH/packer-log.txt")
storageaccount=$(echo "$osdiskuri" | grep -Po '^https://\K([a-zA-Z0-9]+)')

printf "ostype: %s\n" "$ostype"
printf "osdiskuri: %s\n" "$osdiskuri"
printf "storageaccount: %s\n" "$storageaccount"

readarray -d "/" -t version_array <<< "$VE_RELEASE"

az login --service-principal -u "$ARM_CLIENT_ID" -p "$ARM_CLIENT_SECRET" --tenant "$ARM_TENANT_ID"
az account set --subscription "$ARM_SUBSCRIPTION_ID"

az group create \
  --name "$AZ_ACG_RESOURCE_GROUP_NAME" \
  --location "$AZ_LOCATION"

az sig create \
  --resource-group "$AZ_ACG_RESOURCE_GROUP_NAME" \
  --gallery-name "$AZ_ACG_NAME"

az sig image-definition create \
   --resource-group "$AZ_ACG_RESOURCE_GROUP_NAME" \
   --gallery-name "$AZ_ACG_NAME" \
   --gallery-image-definition "${version_array[0]}" \
   --publisher "$VE_IMAGE_PUBLISHER" \
   --offer "$VE_IMAGE_OFFER" \
   --sku "$VE_IMAGE_SKU" \
   --os-type "$ostype" \
   --os-state generalized

readarray -t img_versions <<< "$(az sig image-version list \
  --gallery-image-definition "${version_array[0]}" \
  --gallery-name "$AZ_ACG_NAME" \
  --resource-group "$AZ_ACG_RESOURCE_GROUP_NAME" \
  --output tsv \
  --query '[].name')"

echo "Found ${#img_versions[*]} current version definitions"
echo "Current versions:"
printf "%s\n " "${img_versions[@]}"

# if the image list is empty start at 1.0.0 otherwise increment the last version
if [[ ${#img_versions[*]} -eq 0 ]]
then
  version="1.0.0"
else
  # sort array in reverse version order and get current latest version
  readarray -t sorted < <(for a in "${img_versions[@]}"; do echo "$a"; done | sort -Vr)
  latest="${sorted[0]}"
  # Fix shell script to increment semversion
  # https://stackoverflow.com/questions/59435639/fix-shell-script-to-increment-semversion
  version=$(echo "$latest" | awk 'BEGIN{FS=OFS="."} {$3+=1} 1')
fi


if [[ $version =~ ^[0-9]{1,}\.[0-9]{1,}\.[0-9]{1,} ]]
then
  echo "New version will be $version"
else
  echo "Failed to set new semver version"
  exit 1
fi

az sig image-version create \
  --resource-group "$AZ_ACG_RESOURCE_GROUP_NAME" \
  --gallery-name "$AZ_ACG_NAME" \
  --gallery-image-definition "${version_array[0]}" \
  --gallery-image-version "$version" \
  --os-vhd-storage-account "/subscriptions/$ARM_SUBSCRIPTION_ID/resourceGroups/$AZ_RESOURCE_GROUP_NAME/providers/Microsoft.Storage/storageAccounts/$storageaccount" \
  --os-vhd-uri "$osdiskuri" \
  --tags "source_tag=$VE_RELEASE"
