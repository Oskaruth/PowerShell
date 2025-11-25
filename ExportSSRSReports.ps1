$ReportServerUri = "http://sql4/ReportServer/ReportService2010.asmx?wsdl"
$ExportRoot  = "C:\Project\SSRS"
$ReportPath = "/"  # Start at SSRS root

# Connect to SSRS Web Service
$proxy = New-WebServiceProxy -Uri $ReportServerUri -Namespace SSRS.ReportingService2010 -UseDefaultCredential

# Get all catalog items recursively
$items = $proxy.ListChildren($ReportPath, $true)

foreach ($item in $items) {
    switch ($item.TypeName) {
        "Report" {
            # Standard .rdl report
            $extension = ".rdl"
        }
        "LinkedReport" {
            # Export as .rdl.link to identify it's a linked report
            $extension = ".rdl.link"
        }
        "DataSource" {
            # Shared Data Source
            $extension = ".rsds"
        }
        "DataSet" {
            # Shared Dataset
            $extension = ".rsd"
        }
        Default {
            continue  # Skip items like folders, resources, etc.
        }
    }

    # Build relative path
    $relativePath = $item.Path.TrimStart("/") -replace "/", "\"
    $folderPath = Split-Path -Path (Join-Path $ExportRoot $relativePath)

    # Ensure local directory exists
    if (-not (Test-Path $folderPath)) {
        New-Item -ItemType Directory -Path $folderPath -Force | Out-Null
    }

    # Try to export definition
    try {
        $definition = $proxy.GetItemDefinition($item.Path)
        $filePath = Join-Path $folderPath ($item.Name + $extension)
        [System.IO.File]::WriteAllBytes($filePath, $definition)

        Write-Host "Exported: $filePath"
    } catch {
        Write-Warning "Failed to export $($item.TypeName): $($item.Path) - $($_.Exception.Message)"
    }
}
