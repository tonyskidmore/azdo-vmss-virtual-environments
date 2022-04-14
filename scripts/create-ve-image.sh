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
export AZ_ACG_RESOURCE_GROUP_NAME=${AZ_ACG_RESOURCE_GROUP_NAME:-rg-ve-acg-01}
export AZ_ACG_NAME=${AZ_ACG_NAME:-acg_01}
export VE_IMAGE_PUBLISHER=${VE_IMAGE_PUBLISHER:-actions}
export VE_IMAGE_OFFER=${VE_IMAGE_OFFER:-virtual-environments}
export VE_IMAGE_SKU=${VE_IMAGE_SKU:-Ubuntu2004}
export VE_IMAGE_TYPE=${VE_IMAGE_TYPE:-Ubuntu2004}
export VE_IMAGES_TO_KEEP=${VE_IMAGES_TO_KEEP:-}
export VE_IMAGES_VERSION_START=${VE_IMAGES_VERSION_START:-1.0.0}
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
echo "VE_IMAGES_TO_KEEP=${VE_IMAGES_TO_KEEP}"
echo "VE_IMAGES_VERSION_START=${VE_IMAGES_VERSION_START}"
echo "VE_RELEASE=${VE_RELEASE:-ubuntu20/20220405.4}"
echo "PACKER_LOG=${PACKER_LOG}"
echo "PACKER_LOG_PATH=${PACKER_LOG_PATH}"

if [[ -d "$root_path/virtual-environments" ]] && [[ -n "$root_path" ]]
then
  echo "removing existing $root_path/virtual-environments directory"
  rm -rf "$root_path/virtual-environments"
fi

git clone -b "$VE_RELEASE" --single-branch https://github.com/actions/virtual-environments.git "$root_path/virtual-environments"

# run PowerShell wrapper script to create packer image
pwsh -File "$script_path/create-ve-image.ps1" -NonInteractive

# get required outputs from packer log file
ostype=$(grep -Po '^OSType:\s\K([a-zA-Z]+)$' "$PACKER_LOG_PATH")
osdiskuri=$(grep -Po '^OSDiskUri:\s\K(.+)$' "$PACKER_LOG_PATH")
storageaccount=$(echo "$osdiskuri" | grep -Po '^https://\K([a-zA-Z0-9]+)')

printf "ostype: %s\n" "$ostype"
printf "osdiskuri: %s\n" "$osdiskuri"
printf "storageaccount: %s\n" "$storageaccount"

readarray -d "/" -t version_array <<< "$VE_RELEASE"

echo "Logging into Azure..."
az login --service-principal -u "$ARM_CLIENT_ID" -p "$ARM_CLIENT_SECRET" --tenant "$ARM_TENANT_ID"
az account set --subscription "$ARM_SUBSCRIPTION_ID"

echo "Creating resource group $AZ_ACG_RESOURCE_GROUP_NAME"
az group create \
  --name "$AZ_ACG_RESOURCE_GROUP_NAME" \
  --location "$AZ_LOCATION"

echo "Creating Azure Compute Gallery $AZ_ACG_NAME"
az sig create \
  --resource-group "$AZ_ACG_RESOURCE_GROUP_NAME" \
  --gallery-name "$AZ_ACG_NAME"

echo "Creating Azure Compute Gallery Image Definition $AZ_ACG_NAME"
az sig image-definition create \
   --resource-group "$AZ_ACG_RESOURCE_GROUP_NAME" \
   --gallery-name "$AZ_ACG_NAME" \
   --gallery-image-definition "${version_array[0]}" \
   --publisher "$VE_IMAGE_PUBLISHER" \
   --offer "$VE_IMAGE_OFFER" \
   --sku "$VE_IMAGE_SKU" \
   --os-type "$ostype" \
   --os-state generalized

echo "Getting current Azure Compute Gallery Image Version versions"
# using jq output due to issues with creating bash array with --output tsv
readarray -t img_versions <<< "$(az sig image-version list \
  --gallery-image-definition "${version_array[0]}" \
  --gallery-name "$AZ_ACG_NAME" \
  --resource-group "$AZ_ACG_RESOURCE_GROUP_NAME" \
  --output json \
  --query '[].name' \
  | jq -r .[])"

echo "Found ${#img_versions[*]} current version definitions"
echo "Current versions:"
printf "%s\n " "${img_versions[@]}"

# if the image list is empty start at $VE_IMAGES_VERSION_START otherwise increment the last version
if [[ ${#img_versions[*]} -eq 1 ]] && [[ -z "${img_versions[0]}" ]]
then
  echo "Defaulting version to $VE_IMAGES_VERSION_START"
  version="$VE_IMAGES_VERSION_START"
elif [[ ${#img_versions[*]} -ge 1 ]] && [[ -n "${img_versions[0]}" ]]
  # sort array in reverse version order and get current latest version
  echo "Getting version from az cli output"
  readarray -t sorted < <(for a in "${img_versions[@]}"; do echo "$a"; done | sort -Vr)
  latest="${sorted[0]}"
  # Fix shell script to increment semversion
  # https://stackoverflow.com/questions/59435639/fix-shell-script-to-increment-semversion
  version=$(echo "$latest" | awk 'BEGIN{FS=OFS="."} {$3+=1} 1')
else
  echo "Unable to determine state of image versions"
  exit 1
fi

printf "new version will be: %s\n " "$version"


if [[ $version =~ ^[0-9]{1,}\.[0-9]{1,}\.[0-9]{1,} ]]
then
  echo "Validated version format successfully"
else
  echo "Failed to validate semver for new version"
  exit 1
fi

echo "Creating Azure Compute Gallery Image Version $version"
az sig image-version create \
  --resource-group "$AZ_ACG_RESOURCE_GROUP_NAME" \
  --gallery-name "$AZ_ACG_NAME" \
  --gallery-image-definition "${version_array[0]}" \
  --gallery-image-version "$version" \
  --os-vhd-storage-account "/subscriptions/$ARM_SUBSCRIPTION_ID/resourceGroups/$AZ_RESOURCE_GROUP_NAME/providers/Microsoft.Storage/storageAccounts/$storageaccount" \
  --os-vhd-uri "$osdiskuri" \
  --tags "source_tag=$VE_RELEASE"

# TODO: add image version cleanup
# if [[ -n "$VE_IMAGES_TO_KEEP" ]] && [[ ${#sorted[*]} -gt $VE_IMAGES_TO_KEEP ]]
# then
#   end_index=$(($VE_IMAGES_TO_KEEP - 1))
#   images_to_keep=${sorted[@]:0:$end_index}
#   printf "%s\n" "${images_to_keep[@]}"
# fi