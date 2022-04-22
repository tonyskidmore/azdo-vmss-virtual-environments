#!/bin/bash

set -e

# define variables
start=$(date +%s)
script_path=$(dirname "$(realpath "$0")")
export script_path
echo "script_path: $script_path"
root_path=$(dirname "$script_path")
export root_path
echo "root_path: $root_path"

# functions

# shellcheck disable=SC1091
. "$script_path/bash_functions/array_contains"
# shellcheck disable=SC1091
. "$script_path/bash_functions/check_arm_env_vars"
# shellcheck disable=SC1091
. "$script_path/bash_functions/display_message"

# end functions

# check that ARM_ envionment variables are set
check_arm_env_vars

# Set defaults overridable by environment variables
export AZ_RESOURCE_GROUP_NAME=${AZ_RESOURCE_GROUP_NAME:-rg-ve-images}
export AZ_LOCATION=${AZ_LOCATION:-uksouth}
export AZ_ACG_RESOURCE_GROUP_NAME=${AZ_ACG_RESOURCE_GROUP_NAME:-rg-ve-acg-01}
export AZ_ACG_NAME=${AZ_ACG_NAME:-acg_01}
export VE_REPO=${VE_REPO:-https://github.com/actions/virtual-environments.git}
export VE_IMAGE_PUBLISHER=${VE_IMAGE_PUBLISHER:-actions}
export VE_IMAGE_OFFER=${VE_IMAGE_OFFER:-virtual-environments}
export VE_IMAGE_SKU=${VE_IMAGE_SKU:-Ubuntu2004}
export VE_IMAGE_DEF=${VE_IMAGE_DEF:-ubuntu20}
export VE_IMAGES_TO_KEEP=${VE_IMAGES_TO_KEEP:-2}
export VE_IMAGES_VERSION_START=${VE_IMAGES_VERSION_START:-1.0.0}
# specific tag
# export VE_RELEASE=${VE_RELEASE:-ubuntu20/20220405.4}
# use latest available tag
export VE_RELEASE=${VE_RELEASE:-ubuntu20/latest}
# use a specific commit
# export VE_RELEASE=${VE_RELEASE:-9364605}
export PACKER_NO_COLOR=${PACKER_NO_COLOR:-1}
export PACKER_LOG=${PACKER_LOG:-1}
export PACKER_LOG_PATH=${PACKER_LOG_PATH:-$root_path/packer-log.txt}

echo "AZ_RESOURCE_GROUP_NAME=${AZ_RESOURCE_GROUP_NAME}"
echo "AZ_LOCATION=${AZ_LOCATION}"
echo "AZ_ACG_RESOURCE_GROUP_NAME=${AZ_ACG_RESOURCE_GROUP_NAME}"
echo "AZ_ACG_NAME=${AZ_ACG_NAME}"
echo "VE_REPO=${VE_REPO}"
echo "VE_IMAGE_PUBLISHER=${VE_IMAGE_PUBLISHER}"
echo "VE_IMAGE_OFFER=${VE_IMAGE_OFFER}"
echo "VE_IMAGE_SKU=${VE_IMAGE_SKU}"
echo "VE_IMAGE_DEF=${VE_IMAGE_DEF}"
echo "VE_IMAGES_TO_KEEP=${VE_IMAGES_TO_KEEP}"
echo "VE_IMAGES_VERSION_START=${VE_IMAGES_VERSION_START}"
echo "VE_RELEASE=${VE_RELEASE}"
echo "PACKER_NO_COLOR=${PACKER_NO_COLOR}"
echo "PACKER_LOG=${PACKER_LOG}"
echo "PACKER_LOG_PATH=${PACKER_LOG_PATH}"

if [[ -d "$root_path/virtual-environments" ]] && [[ -n "$root_path" ]]
then
  display_message info "removing existing $root_path/virtual-environments directory"
  rm -rf "$root_path/virtual-environments"
fi

# split release into an array
IFS='/' read -ra version_array <<< "$VE_RELEASE"

# assume that if version_array is a single element and not in the format of version/tag
# that a commit is being passed
if [[ ${#version_array[*]} -eq 1 ]]
then
  display_message info "VE_RELEASE is a commit"
  VE_RELEASE="${version_array[0]}" # commit
  git clone "$VE_REPO" "$root_path/virtual-environments"
  git -C "$root_path/virtual-environments" checkout "$VE_RELEASE"
elif [[ "${version_array[1]}" == "latest" ]]
then
  display_message info "VE_RELEASE wants the latest tag"
  git clone "$VE_REPO" "$root_path/virtual-environments"
  readarray -t tags <<< "$(git -C "$root_path/virtual-environments" tag --list --sort=-committerdate "${version_array[0]}/*")"
  declare -p tags
  latest_tag="${tags[0]}"
  git -C "$root_path/virtual-environments" checkout "$latest_tag"
  VE_RELEASE="$latest_tag"
else
  display_message info "VE_RELEASE is a version/tag"
  git clone -b "$VE_RELEASE" --single-branch "$VE_REPO" "$root_path/virtual-environments"
fi

display_message info "Using release tag: $VE_RELEASE"

display_message info "Logging into Azure..."
az login --service-principal -u "$ARM_CLIENT_ID" -p "$ARM_CLIENT_SECRET" --tenant "$ARM_TENANT_ID"
az account set --subscription "$ARM_SUBSCRIPTION_ID"

display_message info "Creating resource group $AZ_ACG_RESOURCE_GROUP_NAME"
az group create \
  --name "$AZ_ACG_RESOURCE_GROUP_NAME" \
  --location "$AZ_LOCATION"

display_message info "Creating Azure Compute Gallery $AZ_ACG_NAME"
az sig create \
  --resource-group "$AZ_ACG_RESOURCE_GROUP_NAME" \
  --gallery-name "$AZ_ACG_NAME"

# get JSON output of existing image versions
display_message info "Getting current Azure Compute Gallery Image Version versions"
img_versions_json=$(az sig image-version list \
                    --gallery-image-definition "$VE_IMAGE_DEF" \
                    --gallery-name "$AZ_ACG_NAME" \
                    --resource-group "$AZ_ACG_RESOURCE_GROUP_NAME" \
                    --output json)

# read image version names into array
readarray -t img_versions <<< "$(echo "$img_versions_json" | jq -r .[].name)"

# TODO: check for "null" if image versions do not already exist
# check existing tagged versions
readarray -t source_tags <<< "$(echo "$img_versions_json" | jq -r '.[].tags[]')"
declare -p source_tags

if array_contains source_tags "$VE_RELEASE"
then
  display_message warning "Tagged release definition already exists in Azure Compute Gallery: $VE_RELEASE"
  display_message warning "Not attempting to create new version"
  # update to non-zero if you want this to generate an error
  exit 0
else
  # patch PowerShell script to remove interactive cleanup
  # https://www.packer.io/docs/commands/build#on-error-cleanup
  display_message info "Patching: $root_path/virtual-environments/scripts/GenerateResourcesAndImage.ps1"
  # this probably isn't required as I would suspect that running in a pipeline would ignore the packer
  # option to ask about cleanup.  Leaving it in until I'm sure.
  sed -i 's/-on-error=ask//' "$root_path/virtual-environments/helpers/GenerateResourcesAndImage.ps1"
  # run PowerShell wrapper script to create packer image
  display_message info "Running PowerShell script: $script_path/ve-image-create.ps1"
  pwsh -File "$script_path/ve-image-create.ps1" -NonInteractive
fi

# get required outputs from packer log file
ostype=$(grep -Po '^OSType:\s\K([a-zA-Z]+)$' "$PACKER_LOG_PATH")
osdiskuri=$(grep -Po '^OSDiskUri:\s\K(.+)$' "$PACKER_LOG_PATH")
storageaccount=$(echo "$osdiskuri" | grep -Po '^https://\K([a-zA-Z0-9]+)')

if [[ -z $ostype || -z $osdiskuri || -z $storageaccount ]]
then
  display_message error "Failed to get required values from packer log file"
  display_message error "ostype: $ostype"
  display_message error "osdiskuri: $osdiskuri"
  display_message error "storageaccount: $storageaccount"
  exit 1
fi

display_message info "Variables from packer log file:"
display_message info "ostype: $ostype"
display_message info "osdiskuri: $osdiskuri"
display_message info "storageaccount: $storageaccount"

display_message info "Getting current Azure Compute Gallery Image Definitions"
img_def_json=$(az sig image-definition list \
                --gallery-name "$AZ_ACG_NAME" \
                --resource-group "$AZ_ACG_RESOURCE_GROUP_NAME" \
                --output json)

readarray -t img_defs <<< "$(echo "$img_def_json" | jq -r .[].name)"
declare -p img_defs

if array_contains img_defs "$VE_IMAGE_DEF"
then
  display_message warning "Azure Compute Gallery Image Definition $VE_IMAGE_DEF already exists"
else
  display_message info "Creating Azure Compute Gallery Image Definition $VE_IMAGE_DEF"
  az sig image-definition create \
    --resource-group "$AZ_ACG_RESOURCE_GROUP_NAME" \
    --gallery-name "$AZ_ACG_NAME" \
    --gallery-image-definition "$VE_IMAGE_DEF" \
    --publisher "$VE_IMAGE_PUBLISHER" \
    --offer "$VE_IMAGE_OFFER" \
    --sku "$VE_IMAGE_SKU" \
    --os-type "$ostype" \
    --os-state generalized
fi

display_message info "Found ${#img_versions[*]} current VM image version definitions"
display_message info "Current versions:"
echo "${img_versions[@]}"

# if the image list is empty start at $VE_IMAGES_VERSION_START otherwise increment the last version
if [[ ${#img_versions[*]} -eq 1 ]] && [[ -z "${img_versions[0]}" ]]
then
  display_message info "Defaulting version to $VE_IMAGES_VERSION_START"
  version="$VE_IMAGES_VERSION_START"
elif [[ ${#img_versions[*]} -ge 1 ]] && [[ -n "${img_versions[0]}" ]]
then
  # sort array in reverse version order and get current latest version
  display_message info "Getting current latest VM image version"
  readarray -t sorted < <(for a in "${img_versions[@]}"; do echo "$a"; done | sort -Vr)
  latest="${sorted[0]}"
  # Fix shell script to increment semversion
  # https://stackoverflow.com/questions/59435639/fix-shell-script-to-increment-semversion
  version=$(echo "$latest" | awk 'BEGIN{FS=OFS="."} {$3+=1} 1')
else
  display_message error "Unable to determine state of image versions"
  exit 1
fi

display_message info "New VM image version will be: $version"

if [[ $version =~ ^[0-9]{1,}\.[0-9]{1,}\.[0-9]{1,} ]]
then
  display_message info "Validated VM image version semver format successfully"
else
  display_message error "Failed to validate semver for new version"
  exit 1
fi

display_message info "Creating Azure Compute Gallery Image Version $version"
az sig image-version create \
  --resource-group "$AZ_ACG_RESOURCE_GROUP_NAME" \
  --gallery-name "$AZ_ACG_NAME" \
  --gallery-image-definition "$VE_IMAGE_DEF" \
  --gallery-image-version "$version" \
  --os-vhd-storage-account "/subscriptions/$ARM_SUBSCRIPTION_ID/resourceGroups/$AZ_RESOURCE_GROUP_NAME/providers/Microsoft.Storage/storageAccounts/$storageaccount" \
  --os-vhd-uri "$osdiskuri" \
  --tags "source_tag=$VE_RELEASE"

# TODO: validate that the image currently being used by the VMSS is not removed
# VM Image version maintenance
if [[ -n "$VE_IMAGES_TO_KEEP" ]] && [[ ${#sorted[*]} -ge $VE_IMAGES_TO_KEEP ]]
then

  # create array of new version and combine that with the sorted array
  new_version=("$version")
  all_versions=("${new_version[@]}" "${sorted[@]}" )
  declare -p all_versions

  # declare and array of the VM Image versions to keep
  images_to_keep=("${all_versions[@]:0:$VE_IMAGES_TO_KEEP}")
  declare -p images_to_keep

  display_message info "Number of current images: ${#all_versions[*]}"
  display_message info "Number of images to keep: $VE_IMAGES_TO_KEEP"

  display_message info "Current VM Image versions:"
  printf "%s\n" "${all_versions[@]}"
  display_message info "VM Image versions to retain:"
  printf "%s\n" "${images_to_keep[@]}"

  # loop through and remove all VM Image versions that are not required
  for img_ver in "${all_versions[@]}"
  do
    display_message info "Checking VM Image version: $img_ver"
    if array_contains images_to_keep "$img_ver"
    then
      display_message info "Retaining VM Image version: $img_ver"
    else
      display_message warning "Deleting VM Image version: $img_ver"
      az sig image-version delete \
        --resource-group "$AZ_ACG_RESOURCE_GROUP_NAME" \
        --gallery-name "$AZ_ACG_NAME" \
        --gallery-image-definition "$VE_IMAGE_DEF" \
        --gallery-image-version "$img_ver"
    fi
  done
fi

display_message info "Image build script execution completed in $((($(date +%s) - start)/60)) minutes"
