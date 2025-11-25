# --- Configuration Section ---
# SQL Server
$sqlServer = "COREAG"
$sqlDatabase = "YanceyStaging"
$sqlSchema = "dbs"

# Snowflake
$snowflakeUser = "s_D365"
$snowflakePassword = "H3lpful1nt3gr@t3"
$snowflakeSchema = "DBS"
$snowflakeDatabase = "D365"

# Email Settings
$smtpServer = "smtp.yanceybros.com"      
$from = "noreply@yanceybros.com"            
$to = "kevin_wilkie@yanceybros.com"

# --- SQL Server Row Count Collection (includes views) ---
Write-Host "`nGathering SQL Server row counts (tables + views)..." -ForegroundColor Cyan
$sqlConn = New-Object System.Data.SqlClient.SqlConnection
$sqlConn.ConnectionString = "Server=$sqlServer;Database=$sqlDatabase;Integrated Security=True"
$sqlConn.Open()

$sqlCmd = $sqlConn.CreateCommand()
$sqlCmd.CommandText = @"
SELECT 
    ViewName,
    REPLACE(ViewName, 'vw_', '') AS ObjectName,
    TheRowCount
FROM dbs.TheRowCounts
"@

$sqlReader = $sqlCmd.ExecuteReader()

# --- BUILD OBJECT LIST ---
$objects = @()
while ($sqlReader.Read()) {
    $objects += [PSCustomObject]@{
        Name     = $sqlReader["ObjectName"]
        ViewName = $sqlReader["ViewName"]
        RowCount = $sqlReader["TheRowCount"]
    }
}
$sqlReader.Close()

# --- BUILD SQL ROWCOUNT DICTIONARY ---
$sqlRowCounts = @{}
foreach ($obj in $objects) {
    $sqlRowCounts[$obj.Name] = [int]$obj.RowCount
}

$sqlConn.Close()

# --- Snowflake Row Counts ---
Write-Host "`nGathering Snowflake row counts..." -ForegroundColor Cyan
$snowflakeConn = New-Object System.Data.Odbc.OdbcConnection
$snowflakeConn.ConnectionString = "Driver={SnowflakeDSIIDriver};Server=qya08643.east-us-2.azure.snowflakecomputing.com;UID=$snowflakeUser;PWD=$snowflakePassword;Warehouse=HELIOS_WH;Database=$snowflakeDatabase;Schema=$snowflakeSchema"
$snowflakeConn.Open()

$schemaCmd = $snowflakeConn.CreateCommand()
$schemaCmd.CommandText = @"
SELECT 
    CONCAT('[$sqlSchema].[', table_name, ']') AS TableName,
    row_count
FROM $snowflakeDatabase.INFORMATION_SCHEMA.TABLES
WHERE table_schema = '$snowflakeSchema'
  AND table_type = 'BASE TABLE'
"@
$reader = $schemaCmd.ExecuteReader()

$snowflakeRowCounts = @{}
while ($reader.Read()) {
    $tableName = $reader["TableName"]
    $rowCount = [int]$reader["row_count"]
    $snowflakeRowCounts[$tableName] = $rowCount
}
$reader.Close()
$snowflakeConn.Close()

# --- Comparison ---
Write-Host "`nComparing row counts..." -ForegroundColor Cyan
$normalize = { param($x) $x.ToUpper().Trim() }
$allTables = (($sqlRowCounts.Keys + $snowflakeRowCounts.Keys) | Sort-Object -Unique)

$allResults = @()
$mismatches = @()

foreach ($table in $allTables) {
    $sqlCount = if ($sqlRowCounts.ContainsKey($table)) { $sqlRowCounts[$table] } else { "N/A" }
    $sfCount  = if ($snowflakeRowCounts.ContainsKey($table)) { $snowflakeRowCounts[$table] } else { "N/A" }

	if ($sqlCount -is [int] -and $sfCount -is [int]) {
		$diff = $sqlCount - $sfCount
		if ($sqlCount -gt 0) {
			$pctMissing = (($sqlCount - $sfCount) / $sqlCount) * 100
			$pctMissing = [math]::Round($pctMissing, 2)
		} else {
			$pctMissing = "N/A"
		}
	} else {
		$diff = "N/A"
		$pctMissing = "N/A"
	}

	$record = [PSCustomObject]@{
		Table          = $table.ToUpper()
		SQL_Server     = $sqlCount
		Snowflake      = $sfCount
		Difference     = $diff
		PercentMissing = $pctMissing
	}

    $allResults += $record
    if ($diff -ne 0 -and $diff -ne "N/A") {
        $mismatches += $record
    }
}

$totalSQL = $sqlRowCounts.Count
$totalSnowflake = $snowflakeRowCounts.Count
$totalCompared = $allResults.Count

Write-Host "SQL objects found: $totalSQL"
Write-Host "Snowflake tables found: $totalSnowflake"
Write-Host "Tables compared: $totalCompared"

# --- HTML Builders ---
function Build-HtmlTable ($title, $rows) {
    $htmlRows = foreach ($r in $rows) {
        $color = if ($r.Difference -is [int]) {
            if ($r.Difference -gt 0) { "#007BFF" }   # Blue
            elseif ($r.Difference -lt 0) { "#D9534F" } # Red
            else { "#000000" }
        } else { "#000000" }

        "<tr>
            <td>$($r.Table)</td>
            <td style='text-align:right;'>$($r.SQL_Server)</td>
            <td style='text-align:right;'>$($r.Snowflake)</td>
            <td style='text-align:right;color:$color;font-weight:bold;'>$($r.Difference)</td>
			<td style='text-align:right;color:$color;font-weight:bold;'>$($r.PercentMissing)</td>
        </tr>"
    }

    return @"
    <html>
    <body style='font-family:Segoe UI, Arial, sans-serif;'>
        <h2 style='color:#333;'>$title</h2>
        <p>Total SQL Tables: $totalSQL<br>Total Snowflake Tables: $totalSnowflake<br>Total Compared: $totalCompared</p>
        <table style='border-collapse:collapse;width:100%;'>
            <thead>
                <tr style='background-color:#f2f2f2;'>
                    <th style='border:1px solid #ddd;padding:8px;text-align:left;'>Table</th>
                    <th style='border:1px solid #ddd;padding:8px;text-align:right;'>SQL Server</th>
                    <th style='border:1px solid #ddd;padding:8px;text-align:right;'>Snowflake</th>
                    <th style='border:1px solid #ddd;padding:8px;text-align:right;'>Difference</th>
					<th style='border:1px solid #ddd;padding:8px;text-align:right;'>% Missing</th>
                </tr>
            </thead>
            <tbody>
                $($htmlRows -join "`n")
            </tbody>
        </table>
        <p style='font-size:smaller;color:#888;'>Report generated on $(Get-Date)</p>
    </body>
    </html>
"@
}

# --- Send Summary Email (always) ---
$summaryHtml = Build-HtmlTable "DBS Snowflake vs SQL3 - Full Comparison" $allResults
$summarySubject = "DBS Row Count Summary - $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
Send-MailMessage -From $from -To $to -Subject $summarySubject -Body $summaryHtml -BodyAsHtml -SmtpServer $smtpServer

# --- Send Mismatch Email (only if needed) ---
if ($mismatches.Count -gt 0) {
    Write-Host "Differences found! Sending mismatch alert..." -ForegroundColor Yellow
    $mismatchHtml = Build-HtmlTable "DBS Snowflake vs SQL3 - Row Count Mismatch" $mismatches
    $alertSubject = "ALERT: Row Count Mismatch Detected - $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
    Send-MailMessage -From $from -To $to -Subject $alertSubject -Body $mismatchHtml -BodyAsHtml -SmtpServer $smtpServer
} else {
    Write-Host "No mismatches found. All counts aligned." -ForegroundColor Green
}