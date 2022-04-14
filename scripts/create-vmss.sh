#! /bin/bash

az group create \
  --name "$AZ_RESOURCE_GROUP_NAME" \
  --location "$AZ_LOCATION"

az vmss create \
  --name "$AZ_VMSS_NAME" \
  --resource-group "$AZ_RESOURCE_GROUP_NAME" \
  --subnet "/subscriptions/$ARM_SUBSCRIPTION_ID/resourceGroups/$AZ_NET_RESOURCE_GROUP_NAME/providers/Microsoft.Network/virtualNetworks/$AZ_NET_NAME/subnets/$AZ_SUBNET_NAME" \
  --image "$IMG_VERSION_REF" \
  --vm-sku "$AZ_VMSS_VM_SKU" \
  --storage-sku "$AZ_VMSS_STORAGE_SKU" \
  --admin-username "$AZ_VMSS_ADMIN_NAME" \
  --authentication-type SSH \
  --instance-count 0 \
  --disable-overprovision \
  --upgrade-policy-mode manual \
  --single-placement-group false \
  --platform-fault-domain-count 1 \
  --load-balancer "" \
  --os-disk-caching readonly \
  --custom-data custom-data.sh

az vmss update \
  --name "$AZ_VMSS_NAME" \
  --resource-group "$AZ_RESOURCE_GROUP_NAME" \
  --set virtualMachineProfile.diagnosticsProfile='{"bootDiagnostics": {"Enabled" : "True"}}'
