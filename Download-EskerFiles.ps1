<#
.SYNOPSIS
    Downloads specific files from SharePoint (Esker/Files) via Microsoft Graph.

.NOTES
    Requires:
        - Connect-MgGraph with Files.Read.All or Sites.ReadWrite.All
        - Microsoft.Graph modules installed
#>

param(
    [string]$DriveName = "D365_Prod",   # Name of the document library / drive
    [string]$DownloadFolder = "C:\Temp" # Folder to download files to
)

# -----------------------------
# Load file list
# -----------------------------
$SiteUrl = "yanceybros.sharepoint.com:/sites/Information_Technology"   # Replace
$FileListPath = "C:\Project\SQLServerScripts\SharePointFilesToDownload.txt"

if (!(Test-Path $FileListPath)) {
    Write-Error "File list not found: $FileListPath"
    exit 1
}

Write-Host "Loading file names to download from:`n$FileListPath" -ForegroundColor Cyan
$FilesToDownload = Get-Content $FileListPath | Where-Object { $_.Trim() -ne "" }
$FilesToDownload = $FilesToDownload | ForEach-Object { $_.Trim().ToLower() }

if ($FilesToDownload.Count -eq 0) {
    Write-Error "No filenames found in $FileListPath"
    exit 1
}

# -----------------------------
# Resolve SiteId
# -----------------------------
Write-Host "Resolving SiteUrl to SiteId..." -ForegroundColor Cyan

# 1. Get Site
$site = Get-MgSite -SiteId $siteUrl

if (-not $site) {
    Write-Error "Failed to resolve site using search: $SiteUrl"
    exit 1
}

$SiteId = $site.Id
Write-Host "Resolved SiteId: $SiteId" -ForegroundColor Green

# -----------------------------
# Ensure download folder exists
# -----------------------------
if (!(Test-Path $DownloadFolder)) {
    New-Item -ItemType Directory -Path $DownloadFolder | Out-Null
}

# -----------------------------
# Get the correct drive by name
# -----------------------------
$allDrives = Get-MgSiteDrive -SiteId $SiteId
$drive = $allDrives | Where-Object { $_.Name -eq $DriveName } | Select-Object -First 1

if (-not $drive) {
    Write-Error "Could not find the drive named '$DriveName'."
    exit 1
}

$driveId = $drive.Id
Write-Host "Resolved DriveId: $driveId" -ForegroundColor Green

# -----------------------------
# Stepwise folder traversal: Esker -> Files
# -----------------------------
Write-Host "Resolving /Esker/Files folder..." -ForegroundColor Cyan

$eskerFolder = Get-MgDriveItemChild -DriveId $driveId -DriveItemId "root" |
               Where-Object { $_.Name -eq "Esker" }

if (-not $eskerFolder) { Write-Error "Folder 'Esker' not found in root"; exit 1 }

$filesFolder = Get-MgDriveItemChild -DriveId $driveId -DriveItemId $eskerFolder.Id |
               Where-Object { $_.Name -eq "Files" }

if (-not $filesFolder) { Write-Error "Folder 'Files' not found inside 'Esker'"; exit 1 }

$folderId = $filesFolder.Id
Write-Host "Resolved folderId for Esker/Files: $folderId" -ForegroundColor Green

# -----------------------------
# Get all children from Esker/Files
# -----------------------------
function Get-AllDriveItems {
    param([string]$DriveId, [string]$FolderId)
    $allItems = @()
    $uri = "https://graph.microsoft.com/v1.0/drives/$DriveId/items/$FolderId/children"
    do {
        $response = Invoke-MgGraphRequest -Method GET -Uri $uri
        $allItems += $response.value
        $uri = $response.'@odata.nextLink'
    } while ($uri)
    return $allItems
}

Write-Host "Fetching full file list from Esker/Files..." -ForegroundColor Cyan
$allFiles = Get-AllDriveItems -DriveId $driveId -FolderId $folderId

# -----------------------------
# Match requested files (case-insensitive)
# -----------------------------
$targetFiles = $allFiles | Where-Object { $FilesToDownload -contains $_.Name.ToLower() }

$missing = $FilesToDownload | Where-Object { $_ -notin $allFiles.Name.ToLower() }
if ($missing.Count -gt 0) {
    Write-Warning "The following files were NOT found in Esker/Files:"
    $missing | ForEach-Object { Write-Warning " - $_" }
}

if ($targetFiles.Count -eq 0) {
    Write-Warning "No matching files to download."
    return
}

# -----------------------------
# Download files
# -----------------------------
foreach ($file in $targetFiles) {
    $downloadPath = Join-Path $DownloadFolder $file.Name
    $uri = "https://graph.microsoft.com/v1.0/drives/$driveId/items/$($file.Id)/content"

    Write-Host "Downloading $($file.Name)..." -ForegroundColor Yellow
    Invoke-MgGraphRequest -Method GET -Uri $uri -OutputFilePath $downloadPath
}

Write-Host "All requested files downloaded successfully." -ForegroundColor Green
