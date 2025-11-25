# Define parameters
Param(
    [string]$sourceServer,
    [string]$sourceDatabase,
    [string]$sourceTable,
    [string]$targetServer,
    [string]$targetDatabase,
    [string]$destinationTable
)

# Load dbatools module
Import-Module dbatools

# Fetch data from source
try {
	#Log into source
	$ConnectionString = "Server=$sourceServer;Database=$sourceDatabase;TrustServerCertificate=True"
	
    $data = Invoke-DbaQuery -SqlInstance $ConnectionString -Database $sourceDatabase -Query "SELECT DISTINCT * FROM $sourceTable"
    Write-Host "Data fetched successfully from $sourceServer.$sourceDatabase.$sourceTable"
}
catch {
    Write-Error "Error fetching data: $_"
}

# Validate that there are more than 0 records in $data before truncating the table
if ($data.Count -gt 0) {
    try {
		#Log into target 
		$CoreAGConnectionString = "Server=$targetServer;Database=$targetDatabase;TrustServerCertificate=True"
		
        # Clear existing data in target
        Invoke-DbaQuery -SqlInstance $CoreAGConnectionString -Database $targetDatabase -Query "TRUNCATE TABLE $destinationTable"
        Write-Host "Existing data cleared from $targetServer."

        # Insert data into target with retry logic
        $retryCount = 3
        $retryDelay = 5 # seconds
        $success = $false

        for ($i = 0; $i -lt $retryCount; $i++) {
            try {
                # Start a transaction
                $connection = New-Object System.Data.SqlClient.SqlConnection
                $connection.ConnectionString = "Server=$targetServer;Database=$targetDatabase;Integrated Security=True;TrustServerCertificate=True;"
                $connection.Open()
                $transaction = $connection.BeginTransaction()

                # Bulk copy data into the target table
                $bulkCopy = New-Object Data.SqlClient.SqlBulkCopy($connection, [System.Data.SqlClient.SqlBulkCopyOptions]::Default, $transaction)
                $bulkCopy.DestinationTableName = "$targetDatabase.$destinationTable"
				$bulkCopy.BulkCopyTimeout = 300 # Set the timeout to 300 seconds (5 minutes)
				
                $bulkCopy.WriteToServer($data)

                # Commit the transaction
                $transaction.Commit()
                $connection.Close()

                Write-Host "Data inserted successfully into $targetServer.$targetDatabase.$destinationTable"
                $success = $true
                break
            }
            catch {
                Write-Error "Error during data transfer attempt $($i + 1): $_"
                Start-Sleep -Seconds $retryDelay
            }
        }

        if (-not $success) {
            Write-Error "Failed to insert data into $targetServer after $retryCount attempts."
        }
    }
    catch {
        Write-Error "Error during data transfer: $_"
    }
} else {
    Write-Host "No data found to transfer. The destination table was not truncated."
}