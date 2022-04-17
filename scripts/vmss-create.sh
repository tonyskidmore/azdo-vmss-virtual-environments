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

# functions

# shellcheck disable=SC1091
. "$script_path/bash_functions/check_arm_env_vars"

# end functions

check_arm_env_vars

export AZ_ACG_NAME=${AZ_ACG_NAME:-acg_01}
export AZ_ACG_RESOURCE_GROUP_NAME=${AZ_ACG_RESOURCE_GROUP_NAME:-rg-ve-acg-01}
export AZ_ACG_DEF=${AZ_ACG_DEF:-ubuntu20}
export AZ_ACG_VERSION=${AZ_ACG_VERSION:-1.0.0}
export AZ_VMSS_RESOURCE_GROUP_NAME=${AZ_VMSS_RESOURCE_GROUP_NAME:-rg-vmss-azdo-agents-01}
export AZ_LOCATION=${AZ_LOCATION:-uksouth}
export AZ_NET_RESOURCE_GROUP_NAME=${AZ_NET_RESOURCE_GROUP_NAME:-rg-azdo-agents-networks-01}
export AZ_NET_NAME=${AZ_NET_NAME:-vnet-azdo-agents-01}
export AZ_SUBNET_NAME=${AZ_SUBNET_NAME:=snet-azdo-agents-01}
export AZ_VMSS_NAME=${AZ_VMSS_NAME:-vmss-azdo-agents-01}
export AZ_VMSS_VM_SKU=${AZ_VMSS_VM_SKU:-Standard_D2_v3}
export AZ_VMSS_STORAGE_SKU=${AZ_VMSS_STORAGE_SKU:-StandardSSD_LRS}
export AZ_VMSS_ADMIN_NAME=${AZ_VMSS_ADMIN_NAME:-adminuser}
export AZ_VMSS_INSTANCE_COUNT=${AZ_VMSS_INSTANCE_COUNT:-0}
export AZ_VMSS_MANAGED_IDENTITY=${AZ_VMSS_MANAGED_IDENTITY:-true}
export AZ_VMSS_CREATE_RBAC=${AZ_VMSS_CREATE_RBAC:-true}
export IMG_VERSION_REF="/subscriptions/$ARM_SUBSCRIPTION_ID/resourceGroups/$AZ_ACG_RESOURCE_GROUP_NAME/providers/Microsoft.Compute/galleries/$AZ_ACG_NAME/images/$AZ_ACG_DEF/versions/$AZ_ACG_VERSION"

echo "AZ_ACG_NAME: $AZ_ACG_NAME"
echo "AZ_ACG_RESOURCE_GROUP_NAME: $AZ_ACG_RESOURCE_GROUP_NAME"
echo "AZ_ACG_DEF: $AZ_ACG_DEF"
echo "AZ_ACG_VERSION: $AZ_ACG_VERSION"
echo "AZ_VMSS_RESOURCE_GROUP_NAME: $AZ_RESOURCE_GROUP_NAME"
echo "AZ_LOCATION: $AZ_LOCATION"
echo "AZ_NET_RESOURCE_GROUP_NAME: $AZ_NET_RESOURCE_GROUP_NAME"
echo "AZ_NET_NAME: $AZ_NET_NAME"
echo "AZ_SUBNET_NAME: $AZ_SUBNET_NAME"
echo "AZ_VMSS_NAME: $AZ_VMSS_NAME"
echo "AZ_VMSS_VM_SKU: $AZ_VMSS_VM_SKU"
echo "AZ_VMSS_STORAGE_SKU: $AZ_VMSS_STORAGE_SKU"
echo "AZ_VMSS_ADMIN_NAME: $AZ_VMSS_ADMIN_NAME"
echo "AZ_VMSS_INSTANCE_COUNT: $AZ_VMSS_INSTANCE_COUNT"
echo "AZ_VMSS_MANAGED_IDENTITY: $AZ_VMSS_MANAGED_IDENTITY"
echo "AZ_VMSS_CREATE_RBAC: $AZ_VMSS_CREATE_RBAC"
echo "IMG_VERSION_REF: $IMG_VERSION_REF"

echo "Logging into Azure..."
az login --service-principal -u "$ARM_CLIENT_ID" -p "$ARM_CLIENT_SECRET" --tenant "$ARM_TENANT_ID"
az account set --subscription "$ARM_SUBSCRIPTION_ID"

echo "Creating resource group: $AZ_VMSS_RESOURCE_GROUP_NAME"
az group create \
  --name "$AZ_VMSS_RESOURCE_GROUP_NAME" \
  --location "$AZ_LOCATION"

cd "$script_path"

# https://docs.microsoft.com/en-us/azure/devops/pipelines/agents/scale-set-agents?view=azure-devops
echo "Creating vmss: $AZ_VMSS_NAME"
vmss=$(az vmss create \
  --name "$AZ_VMSS_NAME" \
  --resource-group "$AZ_VMSS_RESOURCE_GROUP_NAME" \
  --subnet "/subscriptions/$ARM_SUBSCRIPTION_ID/resourceGroups/$AZ_NET_RESOURCE_GROUP_NAME/providers/Microsoft.Network/virtualNetworks/$AZ_NET_NAME/subnets/$AZ_SUBNET_NAME" \
  --image "$IMG_VERSION_REF" \
  --vm-sku "$AZ_VMSS_VM_SKU" \
  --storage-sku "$AZ_VMSS_STORAGE_SKU" \
  --admin-username "$AZ_VMSS_ADMIN_NAME" \
  --authentication-type SSH \
  --instance-count "$AZ_VMSS_INSTANCE_COUNT" \
  --disable-overprovision \
  --upgrade-policy-mode manual \
  --single-placement-group false \
  --platform-fault-domain-count 1 \
  --load-balancer "" \
  --os-disk-caching readonly \
  --custom-data custom-data.sh \
  --output json)

printf "vmss:\n %s\n" "$vmss"

# az resource wait --exists --ids "/subscriptions/$ARM_SUBSCRIPTION_ID/resourceGroups/$AZ_VMSS_RESOURCE_GROUP_NAME/providers/Microsoft.Compute/virtualMachineScaleSets/$AZ_VMSS_NAME"

vmss_show=$(az vmss show --resource-group "$AZ_VMSS_RESOURCE_GROUP_NAME" --name "$AZ_VMSS_NAME")

vmss_boot_diags_enabled=$(echo "$vmss_show" | jq -r '.virtualMachineProfile.diagnosticsProfile.bootDiagnostics.enabled')


# vmss_boot_diags_enabled=$(echo "$vmss" | jq -r '.virtualMachineProfile.diagnosticsProfile.bootDiagnostics.enabled')
# printf "vmss_boot_diags_enabled: %s\n" "$vmss_boot_diags_enabled"

if [[ $vmss_boot_diags_enabled != "true" ]]
then
  echo "Enabling boot diagnostics $AZ_VMSS_NAME"
  az vmss update \
    --name "$AZ_VMSS_NAME" \
    --resource-group "$AZ_VMSS_RESOURCE_GROUP_NAME" \
    --set virtualMachineProfile.diagnosticsProfile='{"bootDiagnostics": {"Enabled" : "True"}}'
else
  echo "Boot diagnostics for $AZ_VMSS_NAME already enabled"
fi

# Configure managed identities for Azure resources on a virtual machine scale set using Azure CLI
# https://docs.microsoft.com/en-us/azure/active-directory/managed-identities-azure-resources/qs-configure-cli-windows-vmss

if [[ "$AZ_VMSS_MANAGED_IDENTITY" == "true" ]]
then
  echo "Configuring managed identity for $AZ_VMSS_NAME"
  az vmss update \
    --name "$AZ_VMSS_NAME" \
    --resource-group "$AZ_VMSS_RESOURCE_GROUP_NAME" \
    --set identity.type="SystemAssigned"
else
  echo "Not assigning managed identity for $AZ_VMSS_NAME"
fi

# Assign a managed identity access to a resource using Azure CLI
# https://docs.microsoft.com/en-us/azure/active-directory/managed-identities-azure-resources/howto-assign-access-cli

if [[ "$AZ_VMSS_MANAGED_IDENTITY" == "true" ]] && [[ $AZ_VMSS_CREATE_RBAC == "true" ]]
then
  spID=$(az resource list -n "$AZ_VMSS_NAME" --query [*].identity.principalId --out tsv)
  echo "Configuring Contributor access for $AZ_VMSS_NAME Managed Identity $spID on Subscription $ARM_SUBSCRIPTION_ID"
  az role assignment create --assignee "$spID" --role 'Contibutor' --scope "/subscriptions/$ARM_SUBSCRIPTION_ID"
else
  echo "Not assigning RBAC for $AZ_VMSS_NAME identity"
fi
