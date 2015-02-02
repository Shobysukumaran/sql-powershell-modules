cls

$currentPath = (Split-Path $MyInvocation.MyCommand.Definition –Parent)

Import-Module "$currentPath\SQLHelper.psm1" -Force

Set-Location $currentPath

$sourceConnStr = "Integrated Security=SSPI;Persist Security Info=False;Initial Catalog=AdventureWorksDW2012;Data Source=.\sql2014"

$destinationConnStr = "Integrated Security=SSPI;Persist Security Info=False;Initial Catalog=DestinationDB;Data Source=.\sql2014"

$tables = @("[dbo].[DimProduct]", "[dbo].[FactInternetSales]")

$steps = $tables.Count
$i = 1;

$tables |% {
		
	$sourceTableName = $_
	$destinationTableName = $sourceTableName
	
	Write-Progress -activity "Tables Copy" -CurrentOperation "Executing source query over '$sourceTableName'" -PercentComplete (($i / $steps)  * 100) -Verbose
	
	$sourceTable = (Invoke-DBCommand -connectionString $sourceConnStr -commandText "select * from $sourceTableName").Tables[0]
	
	Write-Progress -activity "Tables Copy" -CurrentOperation "Creating destination table '$destinationTableName'" -PercentComplete (($i / $steps)  * 100) -Verbose
	
	Invoke-SQLCreateTable -connectionString $destinationConnStr -table $sourceTable -tableName $destinationTableName -force
	
	Write-Progress -activity "Tables Copy" -CurrentOperation "Loading destination table '$destinationTableName'" -PercentComplete (($i / $steps)  * 100) -Verbose
	
	Invoke-SQLBulkCopy -connectionString $destinationConnStr -data $sourceTable -tableName $destinationTableName				
	
	$i++;
}

Write-Progress -activity "Tables Copy" -Completed
