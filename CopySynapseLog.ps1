# Load required modules and types
Import-Module dbatools
Add-Type -AssemblyName "System.Data"

# Configuration
$sourceServer = "SQLP01"
$sourceDatabase = "D365_PROD"
$sourceTable = "dbo.SynapsePipelineLog"

$targetServer = "SQL3"
$targetDatabase = "D365_PROD"
$targetTable = "dbo.SynapsePipelineLog"

$emailRecipients = "kevin_wilkie@yanceybros.com"
$smtpServer = "smtp.yanceybros.com"

# 1. Get latest InsertedOn from target
try {
    $targetConnectionString = "Server=$targetServer;Database=$targetDatabase;Integrated Security=True;TrustServerCertificate=True"
	$data = Invoke-DbaQuery -SqlInstance $targetServer -Database $targetDatabase -Query "SELECT ISNULL(MAX(InsertedOn), '1900-01-01') AS LatestInsertedOn FROM $targetTable" | 
			Select-Object @{Name='LatestInsertedOn'; Expression={ [datetime]$_.LatestInsertedOn }}

	$data | Format-List

	if ($data[0].LatestInsertedOn) {
		$latestTime = [datetime]$data[0].LatestInsertedOn

        Write-Host "$latestTime found to be the last data in $targetServer.$targetDatabase.$targetTable"
    } else {
        Write-Error "No data returned from MAX(InsertedOn) query. Please verify the target table exists and has correct column names."
        exit 1
    }
}
catch {
    Write-Error "Error fetching latest date: $_"
    exit 1
}

# 2. Get new rows from source
$ts = $latestTime.ToString("yyyy-MM-dd HH:mm:ss.fff")
$queryGetNew = "SELECT * FROM $sourceTable WHERE InsertedOn > '$ts'"

$newRows = Invoke-DbaQuery -SqlInstance $sourceServer -Database $sourceDatabase -Query $queryGetNew

if ($newRows.Count -eq 0) {
    Send-MailMessage -To $emailRecipients `
        -Subject "No New Rows Detected" `
        -Body "No new rows found in $sourceServer.$sourceDatabase.$sourceTable since $latestTime" `
        -From "noreply@yanceybros.com" `
        -SmtpServer $smtpServer

    Write-Host "No new rows. Email sent."
} else {
    # Start a transaction and copy the rows
    $connection = New-Object System.Data.SqlClient.SqlConnection
    $connection.ConnectionString = "Server=$targetServer;Database=$targetDatabase;Integrated Security=True;TrustServerCertificate=True;"
    $connection.Open()
    $transaction = $connection.BeginTransaction()

    $bulkCopy = New-Object Data.SqlClient.SqlBulkCopy($connection, [System.Data.SqlClient.SqlBulkCopyOptions]::Default, $transaction)
    $bulkCopy.DestinationTableName = $targetTable
    $bulkCopy.BulkCopyTimeout = 300

    try {
        $bulkCopy.WriteToServer($newRows)
        $transaction.Commit()
        Write-Host "Data inserted successfully into $targetServer.$targetDatabase.$targetTable"
    } catch {
        $transaction.Rollback()
        Write-Error "Bulk copy failed: $_"
    } finally {
        $connection.Close()
    }
}
