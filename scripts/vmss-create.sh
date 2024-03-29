#! /bin/bash

# Simple script to create a Virtual Machine Scale Set

set -e

# define variables
script_path=$(dirname "$(realpath "$0")")
export script_path
echo "script_path: $script_path"
root_path=$(dirname "$script_path")
export root_path
echo "root_path: $root_path"
vmss_identity_wait_secs=120

# functions

# shellcheck disable=SC1091
. "$script_path/bash_functions/check_arm_env_vars"
# shellcheck disable=SC1091
. "$script_path/bash_functions/display_message"

# end functions

check_arm_env_vars

export AZ_ACG_NAME=${AZ_ACG_NAME:-acg_01}
export AZ_ACG_RESOURCE_GROUP_NAME=${AZ_ACG_RESOURCE_GROUP_NAME:-rg-ve-acg-01}
export AZ_ACG_DEF=${AZ_ACG_DEF:-ubuntu20}
export AZ_ACG_VERSION=${AZ_ACG_VERSION:-1.0.0}
export AZ_LOCATION=${AZ_LOCATION:-uksouth}
export AZ_NET_RESOURCE_GROUP_NAME=${AZ_NET_RESOURCE_GROUP_NAME:-rg-azdo-agents-networks-01}
export AZ_NET_NAME=${AZ_NET_NAME:-vnet-azdo-agents-01}
export AZ_SUBNET_NAME=${AZ_SUBNET_NAME:=snet-azdo-agents-01}
export AZ_VMSS_RESOURCE_GROUP_NAME=${AZ_VMSS_RESOURCE_GROUP_NAME:-rg-vmss-azdo-agents-01}
export AZ_VMSS_NAME=${AZ_VMSS_NAME:-vmss-azdo-agents-01}
export AZ_VMSS_VM_SKU=${AZ_VMSS_VM_SKU:-Standard_D2_v3}
export AZ_VMSS_STORAGE_SKU=${AZ_VMSS_STORAGE_SKU:-StandardSSD_LRS}
export AZ_VMSS_ADMIN_NAME=${AZ_VMSS_ADMIN_NAME:-adminuser}
export AZ_VMSS_INSTANCE_COUNT=${AZ_VMSS_INSTANCE_COUNT:-0}
export AZ_VMSS_MANAGED_IDENTITY=${AZ_VMSS_MANAGED_IDENTITY:-true}
export AZ_VMSS_CREATE_RBAC=${AZ_VMSS_CREATE_RBAC:-true}
export AZ_VMSS_CUSTOM_DATA=${AZ_VMSS_CUSTOM_DATA:-true}
export AZ_VMSS_EXT_CSE=${AZ_VMSS_EXT_CSE:-true}
export AZ_VMSS_EXT_CSE_URI=${AZ_VMSS_EXT_CSE_URI:-https://raw.githubusercontent.com/tonyskidmore/azurerm-vmss-cse/main/cse-vmss-startup.sh}
export AZ_VMSS_EXT_CSE_CMD=${AZ_VMSS_EXT_CSE_CMD:-bash ./cse-vmss-startup.sh}
export IMG_VERSION_REF="/subscriptions/$ARM_SUBSCRIPTION_ID/resourceGroups/$AZ_ACG_RESOURCE_GROUP_NAME/providers/Microsoft.Compute/galleries/$AZ_ACG_NAME/images/$AZ_ACG_DEF/versions/$AZ_ACG_VERSION"

echo "AZ_ACG_NAME: $AZ_ACG_NAME"
echo "AZ_ACG_RESOURCE_GROUP_NAME: $AZ_ACG_RESOURCE_GROUP_NAME"
echo "AZ_ACG_DEF: $AZ_ACG_DEF"
echo "AZ_ACG_VERSION: $AZ_ACG_VERSION"
echo "AZ_LOCATION: $AZ_LOCATION"
echo "AZ_NET_RESOURCE_GROUP_NAME: $AZ_NET_RESOURCE_GROUP_NAME"
echo "AZ_NET_NAME: $AZ_NET_NAME"
echo "AZ_SUBNET_NAME: $AZ_SUBNET_NAME"
echo "AZ_VMSS_RESOURCE_GROUP_NAME: $AZ_VMSS_RESOURCE_GROUP_NAME"
echo "AZ_VMSS_NAME: $AZ_VMSS_NAME"
echo "AZ_VMSS_VM_SKU: $AZ_VMSS_VM_SKU"
echo "AZ_VMSS_STORAGE_SKU: $AZ_VMSS_STORAGE_SKU"
echo "AZ_VMSS_ADMIN_NAME: $AZ_VMSS_ADMIN_NAME"
echo "AZ_VMSS_INSTANCE_COUNT: $AZ_VMSS_INSTANCE_COUNT"
echo "AZ_VMSS_MANAGED_IDENTITY: $AZ_VMSS_MANAGED_IDENTITY"
echo "AZ_VMSS_CREATE_RBAC: $AZ_VMSS_CREATE_RBAC"
echo "AZ_VMSS_CUSTOM_DATA: $AZ_VMSS_CUSTOM_DATA"
echo "AZ_VMSS_EXT_CSE: $AZ_VMSS_EXT_CSE"
echo "AZ_VMSS_EXT_CSE_URI: $AZ_VMSS_EXT_CSE_URI"
echo "AZ_VMSS_EXT_CSE_CMD: $AZ_VMSS_EXT_CSE_CMD"
echo "IMG_VERSION_REF: $IMG_VERSION_REF"

display_message info "Logging into Azure..."
az login --service-principal -u "$ARM_CLIENT_ID" -p "$ARM_CLIENT_SECRET" --tenant "$ARM_TENANT_ID"
az account set --subscription "$ARM_SUBSCRIPTION_ID"

display_message info "Creating resource group: $AZ_VMSS_RESOURCE_GROUP_NAME"
az group create \
  --name "$AZ_VMSS_RESOURCE_GROUP_NAME" \
  --location "$AZ_LOCATION"

cd "$script_path"

# https://docs.microsoft.com/en-us/azure/devops/pipelines/agents/scale-set-agents?view=azure-devops

std_params=("--name" "$AZ_VMSS_NAME"
  "--resource-group" "$AZ_VMSS_RESOURCE_GROUP_NAME"
  "--subnet" "/subscriptions/$ARM_SUBSCRIPTION_ID/resourceGroups/$AZ_NET_RESOURCE_GROUP_NAME/providers/Microsoft.Network/virtualNetworks/$AZ_NET_NAME/subnets/$AZ_SUBNET_NAME"
  "--image" "$IMG_VERSION_REF"
  "--vm-sku" "$AZ_VMSS_VM_SKU"
  "--storage-sku" "$AZ_VMSS_STORAGE_SKU"
  "--admin-username" "$AZ_VMSS_ADMIN_NAME"
  "--authentication-type" "SSH"
  "--instance-count" "$AZ_VMSS_INSTANCE_COUNT"
  "--disable-overprovision"
  "--generate-ssh-keys"
  "--upgrade-policy-mode" "manual"
  "--single-placement-group" "false"
  "--platform-fault-domain-count" "1"
  "--os-disk-caching" "readonly"
  "--output" "json")

custom_data=("--custom-data" "custom-data.sh")

if [[ "$AZ_VMSS_CUSTOM_DATA" == "true" ]]
then
  params=( "${std_params[@]}" "${custom_data[@]}" )
else
  params=( "${std_params[@]}" )
fi

display_message info "Creating vmss: $AZ_VMSS_NAME"
display_message info "Running: az vmss create --load-balancer \"\" ${params[*]}"

vmss=$(az vmss create --load-balancer "" "${params[@]}")

printf "%s\n" "$vmss"

az resource wait --exists --ids "/subscriptions/$ARM_SUBSCRIPTION_ID/resourceGroups/$AZ_VMSS_RESOURCE_GROUP_NAME/providers/Microsoft.Compute/virtualMachineScaleSets/$AZ_VMSS_NAME"

vmss_show=$(az vmss show --resource-group "$AZ_VMSS_RESOURCE_GROUP_NAME" --name "$AZ_VMSS_NAME" --output json)
vmss_boot_diags_enabled=$(echo "$vmss_show" | jq -r '.virtualMachineProfile.diagnosticsProfile.bootDiagnostics.enabled')
vmss_identity=$(echo "$vmss_show" | jq -r '.identity.principalId')

if [[ $vmss_boot_diags_enabled != "true" ]]
then
  display_message info "Enabling boot diagnostics on $AZ_VMSS_NAME"
  az vmss update \
    --name "$AZ_VMSS_NAME" \
    --resource-group "$AZ_VMSS_RESOURCE_GROUP_NAME" \
    --set virtualMachineProfile.diagnosticsProfile='{"bootDiagnostics": {"Enabled" : "True"}}'
else
  display_message warning "Boot diagnostics for $AZ_VMSS_NAME already enabled"
fi


if [[ "$AZ_VMSS_EXT_CSE" == "true" ]]
then
  display_message info "Enabling vmss custom script extension on $AZ_VMSS_NAME"
  settings="{ \"fileUris\": [\"$AZ_VMSS_EXT_CSE_URI\"], \"commandToExecute\": \"$AZ_VMSS_EXT_CSE_CMD\" }"
  # https://docs.microsoft.com/en-us/azure/devops/pipelines/agents/scale-set-agents?view=azure-devops#customizing-virtual-machine-startup-via-the-custom-script-extension
  az vmss extension set \
  --vmss-name "$AZ_VMSS_NAME" \
  --resource-group "$AZ_VMSS_RESOURCE_GROUP_NAME" \
  --name CustomScript \
  --version 2.0 \
  --publisher Microsoft.Azure.Extensions \
  --settings "$settings"
else
  display_message warning "Not enabling vmss custom script extension on $AZ_VMSS_NAME"
fi


# Configure managed identities for Azure resources on a virtual machine scale set using Azure CLI
# https://docs.microsoft.com/en-us/azure/active-directory/managed-identities-azure-resources/qs-configure-cli-windows-vmss

if [[ "$AZ_VMSS_MANAGED_IDENTITY" == "true" ]] && [[ "$vmss_identity" == "null" ]]
then
  display_message info "Configuring managed identity for $AZ_VMSS_NAME"
  az vmss update \
    --name "$AZ_VMSS_NAME" \
    --resource-group "$AZ_VMSS_RESOURCE_GROUP_NAME" \
    --set identity.type="SystemAssigned"
else
  display_message warning "Not assigning a new managed identity for $AZ_VMSS_NAME"
fi

# Assign a managed identity access to a resource using Azure CLI
# https://docs.microsoft.com/en-us/azure/active-directory/managed-identities-azure-resources/howto-assign-access-cli
if [[ "$AZ_VMSS_MANAGED_IDENTITY" == "true" ]] && [[ $AZ_VMSS_CREATE_RBAC == "true" ]]
then
  # wait until the identity property is present, will return "" if found
  display_message info "Waiting for managed identity for $AZ_VMSS_NAME, timeout after $vmss_identity_wait_secs seconds"
  identity=$(az resource wait \
             --name "$AZ_VMSS_NAME" \
             --resource-group "$AZ_VMSS_RESOURCE_GROUP_NAME" \
             --resource-type Microsoft.Compute/virtualMachineScaleSets \
             --timeout "$vmss_identity_wait_secs" \
             --custom "identity" \
             --output tsv)

  if [[ -z "$identity" ]]
  then
    vmss_show=$(az vmss show --resource-group "$AZ_VMSS_RESOURCE_GROUP_NAME" --name "$AZ_VMSS_NAME" --output json)
    vmss_identity=$(echo "$vmss_show" | jq -r '.identity.principalId')
    roles=( "Contributor" "User Access Administrator" )
    for role in "${roles[@]}"
    do
      display_message info "Configuring $role access for $AZ_VMSS_NAME VMSS Managed Identity $vmss_identity on Subscription $ARM_SUBSCRIPTION_ID"
      az role assignment create \
        --assignee-object-id "$vmss_identity" \
        --assignee-principal-type ServicePrincipal \
        --role "$role" \
        --scope "/subscriptions/$ARM_SUBSCRIPTION_ID"
    done
  else
    display_message warning "No identity found for $AZ_VMSS_NAME"
  fi
else
  display_message warning "Not assigning RBAC for $AZ_VMSS_NAME identity"
fi
