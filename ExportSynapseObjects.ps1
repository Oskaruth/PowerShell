# CONFIG
$workspaceName = "yanceyd365prodsynapsewksp"
$resourceGroup = "RESG-D365Production_Int"
$basePath = "C:\SynapseBackup"

# Ensure you're logged in
Connect-AzAccount

# Create folders
$artifactTypes = @{
    "Datasets"       = "Get-AzSynapseDataset"
    "Pipelines"      = "Get-AzSynapsePipeline"
    "Triggers"       = "Get-AzSynapseTrigger"
    "LinkedServices" = "Get-AzSynapseLinkedService"
    "Dataflows"      = "Get-AzSynapseDataFlow"
}

foreach ($type in $artifactTypes.Keys) {
    $folder = Join-Path $basePath $type
    if (-not (Test-Path $folder)) {
        New-Item -ItemType Directory -Path $folder | Out-Null
    }

    Write-Host "`nExporting $type..."
    $cmd = $artifactTypes[$type]
    $artifacts = & $cmd -WorkspaceName $workspaceName -ResourceGroupName $resourceGroup

    foreach ($item in $artifacts) {
        $name = $item.Name
        $json = & $cmd -WorkspaceName $workspaceName -ResourceGroupName $resourceGroup -Name $name | ConvertTo-Json -Depth 20
        $safeName = $name -replace '[\\/:*?"<>|]', "_"  # sanitize
        $path = Join-Path $folder "$safeName.json"
        $json | Out-File -FilePath $path -Encoding UTF8
    }
}
