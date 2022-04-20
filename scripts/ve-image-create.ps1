Write-Output "script_path=$env:script_path"
Write-Output "root_path=$env:root_path"

Import-Module $env:root_path/virtual-environments/helpers/GenerateResourcesAndImage.ps1

$params = @{
  SubscriptionId = "$env:ARM_SUBSCRIPTION_ID"
  ResourceGroupName = "$env:AZ_RESOURCE_GROUP_NAME"
  ImageGenerationRepositoryRoot = "$env:root_path/virtual-environments"
  ImageType = "$env:VE_IMAGE_DEF"
  AzureLocation = "$env:AZ_LOCATION"
  AzureClientId = "$env:ARM_CLIENT_ID"
  AzureClientSecret = "$env:ARM_CLIENT_SECRET"
  AzureTenantId = "$env:ARM_TENANT_ID"
}

GenerateResourcesAndImage @params -Force -RestrictToAgentIpAddress:$true
