# =============================
# CONFIGURATION
# =============================
$SiteUrl = "yanceybros.sharepoint.com:/sites/Information_Technology"
$LibraryName = "D365_Prod"
$FolderPathInLibrary = "Esker/Files"
$DownloadPath = "C:\SharePointDownloads"
# =============================

# --- Install & import Microsoft.Graph module if missing ---
if (-not (Get-Module -ListAvailable -Name Microsoft.Graph)) {
    Install-Module Microsoft.Graph -Scope CurrentUser -Force -AllowClobber
}
Import-Module Microsoft.Graph

# --- Connect interactively to Microsoft Graph ---
Write-Host "Connecting to Microsoft Graph..."
Connect-MgGraph -Scopes "Sites.Read.All","Files.Read.All"

# --- Ensure download folder exists ---
if (-not (Test-Path $DownloadPath)) {
    New-Item -ItemType Directory -Path $DownloadPath | Out-Null
}

# --- Get the SharePoint site ---
Write-Host "Getting site info..."
$site = Get-MgSite -SiteId $SiteUrl

# --- List all document libraries and find target ---
$drives = Get-MgSiteDrive -SiteId $site.Id
$libraryDrive = $drives | Where-Object { $_.Name -eq $LibraryName }
if (-not $libraryDrive) { throw "Document library '$LibraryName' not found." }

# --- Resolve the folder ---
Write-Host "Resolving folder '$FolderPathInLibrary'..."
$folderItem = Get-MgDriveItem -DriveId $libraryDrive.Id -DriveItemId "root:/$FolderPathInLibrary"

# --- Function to get all pages of children ---
function Get-AllDriveItems {
    param(
        [string]$DriveId,
        [string]$FolderId
    )

    $allItems = @()
    $uri = "https://graph.microsoft.com/v1.0/drives/$DriveId/items/$FolderId/children"

    do {
        $response = Invoke-MgGraphRequest -Method GET -Uri $uri
        $allItems += $response.value
        $uri = $response.'@odata.nextLink'
    } while ($uri)

    return $allItems
}

# --- Retrieve all items recursively ---
Write-Host "Retrieving all files (this may take a while)..."
$allFiles = Get-AllDriveItems -DriveId $libraryDrive.Id -FolderId $folderItem.Id

# --- Convert timestamps and filter by Modified date range ---
$startDate = [datetime]"2025-10-01T00:00:00Z"
$endDate   = [datetime]"2025-10-31T23:59:59Z"

$filteredFiles = $allFiles | Where-Object {
    $_.file -and
    ([datetime]$_.lastModifiedDateTime -ge $startDate) -and
    ([datetime]$_.lastModifiedDateTime -le $endDate)
}

Write-Host "Found $($filteredFiles.Count) files modified in October 2025."

# --- Get access token from the current Graph session ---
$graphContext = Get-MgContext
$token = $graphContext.AuthToken
$headers = @{ Authorization = "Bearer $token" }

# --- Download each filtered file ---
foreach ($item in $filteredFiles) {
    $localFile = Join-Path $DownloadPath $item.name

    if (Test-Path $localFile) {
        Write-Host "Skipping $($item.name) — already downloaded."
        continue
    }

    Write-Host "Downloading $($item.name)..."

    try {
        # Retrieve file content as a stream and write manually
        Get-MgDriveItemContent -DriveId $libraryDrive.Id -DriveItemId $item.Id -OutFile $localFile

    }
    catch {
        Write-Warning "Failed to download $($item.name): $($_.Exception.Message)"
    }
}


Write-Host "Download complete! Saved to $DownloadPath"