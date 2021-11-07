param(
    [string]
    $PAT = $env:SYSTEM_ACCESSTOKEN,

    [int]
    $PoolId,

    [string]
    $ServiceEndpointId,

    [string]
    $ServiceEndpointScope,

    [string]
    $AzureId
)

$projectName = "vmss"

$org = "anthony-skidmore"
$method = "GET"
$url = "https://dev.azure.com/$org/_apis/distributedtask/elasticpools?api-version=6.1-preview.1"


$token = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes(":$($PAT)"))

#Set authorization headers
Write-Host Set authorization headers
$headers = @{authorization = "Basic $token" }

#Invoke REST API
Write-Host Invoke REST API

$url= "https://dev.azure.com/$org/_apis/projects?api-version=6.1-preview.4"
$projects = Invoke-RestMethod $url -Method $method -Headers $headers -ContentType 'application/json'

Write-Host "Found $($projects.count) projects"

foreach ($project in $projects.value) {
    $project
}

$projectId = ($projects.value).Where( { $_.name -eq $projectName }).id


$url = "https://dev.azure.com/$org/_apis/distributedtask/elasticpools?api-version=6.1-preview.1"

$pools = Invoke-RestMethod $url -Method $method -Headers $headers -ContentType 'application/json'

Write-Host "Found $($pools.count) elastic pools"
$pools.value

foreach ($pool in $pools.value) {
    $url = "https://dev.azure.com/$org/_apis/distributedtask/elasticpools/$($pool.poolId)?api-version=6.1-preview.1"
    $getPool = Invoke-RestMethod $url -Method $method -Headers $headers -ContentType 'application/json'
    $getPool.value
}

# https://docs.microsoft.com/en-us/rest/api/azure/devops/distributedtask/elasticpools/create?view=azure-devops-rest-6.1
# POST https://dev.azure.com/{organization}/_apis/distributedtask/elasticpools?poolName={poolName}&authorizeAllPipelines={authorizeAllPipelines}&autoProvisionProjectPools={autoProvisionProjectPools}&projectId={projectId}&api-version=6.1-preview.1
$poolName = "vmss-azdo-agents-01"
$url = "https://dev.azure.com/$org/_apis/distributedtask/elasticpools?poolName=$poolName&api-version=6.1-preview.1&projectId=$projectId"
$method = "POST"
$body = @{
    poolId               = $PoolId
    serviceEndpointId    = $ServiceEndpointId
    serviceEndpointScope = $ServiceEndpointScope
    azureId              = $AzureId
    maxCapacity          = 1
    desiredIdle          = 0
    recycleAfterEachUse  = $false
    maxSavedNodeCount    = 0
    osType               = "linux"
    state                = "online"
    offlineSince         = ""
    desiredSize          = 0
    sizingAttempts       = 0
    agentInteractiveUI   = $false
    timeToLiveMinutes    = 30
}

$bodyJson = $body | ConvertTo-Json

$createElasticPool = Invoke-RestMethod $url -Method $method -Headers $headers -ContentType 'application/json' -Body $bodyJson
$createElasticPool.elasticPool
$createElasticPool.agentPool
$createElasticPool.agentQueue
