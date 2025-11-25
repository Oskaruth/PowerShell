####################################################
# Start of Profile
####################################################
$date = Get-Date -f "yyyyMMdd_HHmmss"
Start-Transcript -Path "$(Split-Path $profile)\Transcript_$date.txt"

Register-EngineEvent PowerShell.Exiting -Action { Stop-Transcript } -SupportEvent

if (Test-Path -path "$(Split-Path $profile)\History.clixml") {
    $history = Import-Clixml -Path "$(Split-Path $profile)\History.clixml"
    $history | Add-History
}

function Exit-Me {
    Stop-Transcript
    Get-History | Where-Object ExecutionStatus -eq "Completed" | Export-Clixml -Path "$(Split-Path $profile)\History.clixml"
    Exit
}

function Get-MyOsAssemblies {
    [Appdomain]::CurrentDomain.GetAssemblies() | select-Object FullName | Sort-Object FullName
}

Invoke-Expression "function $([char]4) { Exit-Me }"

########################################################
# SQL Context Detection
########################################################
function Get-SqlContext {
    $path = (Get-Location).Path
    $instance = $null
    $database = $null

    if ($path -match "(?i)(sql|mssql|instances?)\\([^\\]+)") {
        $instance = $matches[2]
    } elseif ($path -match "(?i)([^\\]+)\\(sql|mssql)") {
        $instance = $matches[1]
    }

    if ($path -match "(?i)\\db_?([^\\]+)$") {
        $database = $matches[1]
    }

    return [PSCustomObject]@{
        Instance = $instance
        Database = $database
    }
}

########################################################
# Azure CLI Status
########################################################
function Get-AzCliStatus {
    try {
        $raw = az account show --query "user.name" -o tsv 2>$null
        if ($LASTEXITCODE -eq 0 -and $raw) { return "AZ: $raw" }
        else { return "AZ: not logged in" }
    } catch { return "AZ: not installed" }
}

########################################################
# dbatools Recent Servers Autocomplete
########################################################
if (-not (Test-Path "$env:APPDATA\dbatools-recent.txt")) {
    New-Item "$env:APPDATA\dbatools-recent.txt" -ItemType File -Force | Out-Null
}

function Add-RecentSqlServer([string]$Server) {
    if (-not $Server) { return }
    $servers = Get-Content "$env:APPDATA\dbatools-recent.txt" | Select-Object -Unique
    if ($servers -notcontains $Server) { Add-Content "$env:APPDATA\dbatools-recent.txt" $Server }
}

Register-ArgumentCompleter -CommandName Connect-DbaInstance -ParameterName SqlInstance -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete)
    Get-Content "$env:APPDATA\dbatools-recent.txt" | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
    }
}

########################################################
# Add-ons
########################################################

# Background warm-cache dbatools
Start-Job -ScriptBlock {
    Import-Module dbatools -ErrorAction SilentlyContinue
} | Out-Null

# Quick SQL test
function sql {
    param([string]$Server, [string]$Db = "master")
    Invoke-DbaQuery -SqlInstance $Server -Database $Db -Query "SELECT @@SERVERNAME AS ServerName, SYSDATETIME() AS Time"
}

# List all of the active connections on a server
function Get-ActiveConnections {
    param([string]$Server = "localhost")
    Invoke-DbaQuery -SqlInstance $Server -Query "SELECT db_name(dbid) as DBName, COUNT(*) as Connections FROM sys.sysprocesses GROUP BY dbid"
}

# Which (Linux-style)
Set-Alias which Get-Command

# Shortcut: jump to profile directory
function gl { Set-Location (Split-Path $profile) }

# Git branch function
function Get-GitBranch {
    try {
        $branch = git rev-parse --abbrev-ref HEAD 2>$null
        if ($branch -and $branch -ne 'HEAD') { return " [$branch]" }
    } catch {}
    return ""
}

# Enhance error display
if ($PSVersionTable.PSVersion.Major -ge 7) {
    $PSStyle.Formatting.Error = "`e[91m"
    $PSStyle.Formatting.Warning = "`e[93m"
}

# Restart PowerShell
function restart-ps {
    Start-Process pwsh
    Exit-Me
}

########################################################
# Prompt
########################################################
function prompt {
    $host.UI.RawUI.WindowTitle = "$ENV:USERNAME@$ENV:COMPUTERNAME - $(Get-Location)"

    $lastCommand = Get-History -Count 1
    $nextId = $lastCommand.Id + 1
    $ElapsedTime = ($LastCommand.EndExecutionTime - $LastCommand.StartExecutionTime).TotalSeconds

    $sql = Get-SqlContext
    $az = Get-AzCliStatus

    Write-Host (Get-Date -Format G) -NoNewline -ForegroundColor Red
    Write-Host " :: " -NoNewline -ForegroundColor DarkGray
    Write-Host "[$($ElapsedTime) s]" -NoNewline -ForegroundColor Yellow

    Write-Host " :: " -NoNewline -ForegroundColor DarkGray
    Write-Host $(Get-Location) -NoNewline -ForegroundColor Green

    if ($sql.Instance -or $sql.Database) {
        Write-Host " :: " -NoNewline -ForegroundColor DarkGray
        Write-Host "SQL:" -NoNewline -ForegroundColor Cyan
        if ($sql.Instance) { Write-Host " $($sql.Instance)" -NoNewline -ForegroundColor Magenta }
        if ($sql.Database) { Write-Host " [$($sql.Database)]" -NoNewline -ForegroundColor Blue }
    }

    Write-Host " :: $az" -NoNewline -ForegroundColor DarkYellow

    $wid = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $prp = New-Object System.Security.Principal.WindowsPrincipal($wid)
    $adm = [System.Security.Principal.WindowsBuiltInRole]::Administrator
    $IsAdmin = $prp.IsInRole($adm)

    if ($IsAdmin) {
        $host.UI.RawUI.WindowTitle += " - Administrator"
        Write-Host " [$nextId] #" -NoNewline -ForegroundColor Gray
        return " "
    } else {
        Write-Host " [$nextId] >" -NoNewline -ForegroundColor Gray
        return " "
    }
}

########################################################
# End Profile
########################################################
