# Define export root directory
$exportRoot = "C:\PowerBIExports"
if (-not (Test-Path -Path $exportRoot)) {
    New-Item -Path $exportRoot -ItemType Directory | Out-Null
}

# Log in as your Power BI user (interactive)
Connect-PowerBIServiceAccount

# Get all workspaces (groups) you can access
$workspaces = Get-PowerBIWorkspace -All

foreach ($workspace in $workspaces) {
    Write-Host "`nChecking workspace: $($workspace.Name)" -ForegroundColor Cyan

    # Get all reports in the workspace
    $reports = Get-PowerBIReport -WorkspaceId $workspace.Id

    foreach ($report in $reports) {
        Write-Host "  Exporting: $($report.Name)" -ForegroundColor Green

        # Export file path
        $folderPath = Join-Path -Path $exportRoot -ChildPath $workspace.Name
        if (-not (Test-Path $folderPath)) {
            New-Item -Path $folderPath -ItemType Directory | Out-Null
        }

        $outputFile = Join-Path -Path $folderPath -ChildPath ($report.Name + ".pbix")

        try {
            Export-PowerBIReport `
                -Id $report.Id `
                -WorkspaceId $workspace.Id `
                -OutFile $outputFile

            Write-Host "    ✅ Exported to $outputFile" -ForegroundColor Yellow
        }
        catch {
            Write-Warning "    ❌ Failed to export '$($report.Name)': $_"
        }
    }
}
