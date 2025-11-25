# --- Configuration Section ---
# SQL Server
$sqlServer = "COREAG"
$sqlDatabase = "GDCDM"
$sqlSchema = "dbo"

# Snowflake
$dsn = "Helios_SF"
$snowflakeUser = "s_D365"
$snowflakePassword = "Hahahahahahahahahahah"
$snowflakeSchema = "PUBLIC"
$snowflakeDatabase = "HELIOS"

# Email Settings
$smtpServer = "smtp.nope.com"      
$from = "noreply@nope.com"            
$to = "kevin_wilkie@nope.com"              
$subject = "Snowflake vs SQL Server Row Count Comparison Report"
$body = "Attached is the latest RowCountComparison.csv report."
$attachment = ".\RowCountComparison.csv"

# --- SQL Server Row Count Collection (includes views) ---
Write-Host "`nGathering SQL Server row counts (tables + views)..." -ForegroundColor Cyan
$sqlConn = New-Object System.Data.SqlClient.SqlConnection
$sqlConn.ConnectionString = "Server=$sqlServer;Database=$sqlDatabase;Integrated Security=True"
$sqlConn.Open()

$sqlCmd = $sqlConn.CreateCommand()
$sqlCmd.CommandText = @"
SELECT 
    CONCAT('$sqlSchema.', name) AS ObjectName,
    type_desc
FROM sys.objects
WHERE type IN ('V')  -- U = user table, V = view
  AND schema_id = SCHEMA_ID('$sqlSchema')
  AND name NOT LIKE '%_TEMP'
ORDER BY name
"@
$sqlReader = $sqlCmd.ExecuteReader()

$objects = @()
while ($sqlReader.Read()) {
    $objects += @{
        Name = $sqlReader["ObjectName"]
        Type = $sqlReader["type_desc"]
    }
}
$sqlReader.Close()

$sqlRowCounts = @{}
foreach ($obj in $objects) {
    $objectName = $obj["Name"]
    try {
        $sqlCmd = $sqlConn.CreateCommand()
        $sqlCmd.CommandText = "SELECT COUNT(1) AS Cnt FROM $sqlSchema.vw_$objectName"
        $count = $sqlCmd.ExecuteScalar()
        $sqlRowCounts[$objectName] = [int]$count
    } catch {
        Write-Warning "Failed to get count for $objectName in SQL Server: $_"
        $sqlRowCounts[$objectName] = "Error"
    }
}
$sqlConn.Close()

# --- Snowflake Row Counts ---
Write-Host "`nGathering Snowflake row counts..." -ForegroundColor Cyan
$snowflakeConn = New-Object System.Data.Odbc.OdbcConnection
$snowflakeConn.ConnectionString = "Driver={SnowflakeDSIIDriver};Server=nope.east-us-2.azure.snowflakecomputing.com;UID=$snowflakeUser;PWD=$snowflakePassword;Warehouse=BIG_WH;Database=$snowflakeDatabase;Schema=$snowflakeSchema"
$snowflakeConn.Open()

$schemaCmd = $snowflakeConn.CreateCommand()
$schemaCmd.CommandText = @"
SELECT 
    CONCAT('$sqlSchema.', table_name) AS TableName,
    row_count
FROM $snowflakeDatabase.INFORMATION_SCHEMA.TABLES
WHERE table_schema = '$snowflakeSchema'
AND table_name not ilike '%_Daily'
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
    } else {
        $diff = "N/A"
    }

    $record = [PSCustomObject]@{
        Table      = $table.ToUpper()
        SQL_Server = $sqlCount
        Snowflake  = $sfCount
        Difference = $diff
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
$summaryHtml = Build-HtmlTable "Craziness" $allResults
$summarySubject = "Row Count Summary - $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
Send-MailMessage -From $from -To $to -Subject $summarySubject -Body $summaryHtml -BodyAsHtml -SmtpServer $smtpServer

# --- Send Mismatch Email (only if needed) ---
if ($mismatches.Count -gt 0) {
    Write-Host "`nDifferences found! Sending mismatch alert..." -ForegroundColor Yellow
    $mismatchHtml = Build-HtmlTable " Snowflake vs SQL Server - Row Count Mismatch" $mismatches
    $alertSubject = "ALERT: Row Count Mismatch Detected - $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
    Send-MailMessage -From $from -To $to -Subject $alertSubject -Body $mismatchHtml -BodyAsHtml -SmtpServer $smtpServer
} else {
    Write-Host "`nNo mismatches found. All counts aligned." -ForegroundColor Green

}
