# Load SSIS assemblies
Add-Type -Path "C:\Program Files (x86)\Microsoft SQL Server Management Studio 21\Common7\IDE\Extensions\Microsoft\SQL\Integration Services\Microsoft.SqlServer.Management.IntegrationServices.dll"
Add-Type -Path "C:\Program Files (x86)\Microsoft SQL Server Management Studio 21\Common7\IDE\Extensions\Microsoft\SQL\Microsoft.Data.SqlClient.dll"

# Connect to server
$serverName = "SQL3"
$sqlConn = New-Object Microsoft.SqlServer.Management.Common.ServerConnection $serverName
$integrationServices = New-Object Microsoft.SqlServer.Management.IntegrationServices.IntegrationServices $sqlConn

# SSISDB catalog
$catalog = $integrationServices.Catalogs["SSISDB"]

# Destination for exports
$exportPath = "C:\Project\SSISExports"

foreach ($folder in $catalog.Folders)
{
    foreach ($project in $folder.Projects)
    {
        $ispacFile = Join-Path $exportPath "$($project.Name).ispac"
        Write-Host "Exporting $($project.Name) to $ispacFile"
        $project.Export($ispacFile)

        # Optionally unzip to get .dtsx files
        Expand-Archive -Path $ispacFile -DestinationPath (Join-Path $exportPath $project.Name) -Force
    }
}
