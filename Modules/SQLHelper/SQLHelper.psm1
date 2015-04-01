﻿<# 

Checkout more products and samples at:
	- http://devscope.net/
	- https://github.com/DevScope

Copyright (c) 2015 DevScope

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

#>

function Get-SQLConnection
{
<#
.SYNOPSIS
    Gets a DBConnection object of the specified provider to a connectionstring
		
 .EXAMPLE
        Get-SQLConnection -providerName "System.Data.SqlClient" -connectionString "Integrated Security=SSPI;Persist Security Info=False;Initial Catalog=DomusSocialDW;Data Source=.\sql2014" -Open
		Gets a DBConnection of type SqlConnection and open it
#>
	[CmdletBinding()]
	param(				
		[Parameter(Mandatory=$false)] [string] $providerName = "System.Data.SqlClient",		
		[Parameter(Mandatory=$true)] [string] $connectionString,
		[switch] $open = $false
		)			
	
	if ([string]::IsNullOrEmpty($providerName))
	{
		throw "ProviderName cannot be null";
	}
			
	$providerFactory = [System.Data.Common.DBProviderFactories]::GetFactory($providerName) 	
	
    $connection = $providerFactory.CreateConnection()
			
	$connection.ConnectionString = $connectionString
	
	if ($open)
	{
		Write-Verbose ("Opening Connection to: '{0}'" -f $connection.ConnectionString)
				
		$connection.Open()
	}
		
	Write-Output $connection
}

function Invoke-SQLCommand{
<#
.SYNOPSIS
    Invokes a SQLCommand of type: "Query", "QueryAsTable", "QueryAsDataSet", "NonQuery", "Scalar", "Reader", "Schema"
		
 .EXAMPLE
        Invoke-SQLCommand -connectionString "<connStr>" -commandText "select * from [table]"
		Executes the SQL select command and returns to the pipeline a hashtable representing the row columns

#>
	[CmdletBinding(DefaultParameterSetName = "connStr")]
	param(						
		[Parameter(Mandatory=$false, ParameterSetName = "connStr")] [string] $providerName = "System.Data.SqlClient",
		[Parameter(Mandatory=$true, ParameterSetName = "connStr")] [string] $connectionString,
		[Parameter(Mandatory=$true, ParameterSetName = "conn")] [System.Data.Common.DbConnection] $connection,
		[Parameter(Mandatory=$false, ParameterSetName = "conn")] [System.Data.SqlClient.SqlTransaction] $transaction,		
		[ValidateSet("Query", "QueryAsTable", "QueryAsDataSet", "NonQuery", "Scalar", "Reader", "Schema")] [string] $executeType = "Query",
		[Parameter(Mandatory=$true)] [string] $commandText,		
		$parameters = $null,
		[int] $commandTimeout = 300
		)

	try
	{				 								
		if ($PsCmdlet.ParameterSetName -eq "connStr")
		{															
			$connection = Get-SQLConnection -providerName $providerName -connectionString $connectionString -open						
		}
		
		if ($executeType -eq "Schema") 
		{	  
			$dataTable = $connection.GetSchema($commandText)			

			Write-Output (,$dataTable)			
		}
		else
		{		
			$cmd = $connection.CreateCommand()
			
			$cmd.CommandText = $commandText
		
		   	$cmd.CommandTimeout = $commandTimeout			
			
			$cmd.Transaction = $transaction
			
			if ($parameters -ne $null)
			{			
				if ($parameters -is [hashtable])
				{
					$parameters.GetEnumerator() |% {
						$cmd.Parameters.AddWithValue($_.Name, $_.Value)	| Out-Null
					}
				}
				elseif ($parameters -is [array])
				{
					if ($parameters[0] -is [System.Data.IDataParameter])
					{
						$parameters |% {
							$cmd.Parameters.Add($_) | Out-Null
						}
					}
					else
					{
						for($i = 0; $i -lt $parameters.Count; $i++)
						{
							$paramValue = $parameters[$i]
							$cmd.Parameters.AddWithValue("P$($i + 1)", $paramValue)	| Out-Null
						}						
					}
				}
				else
				{
					throw "Invalid type for '-parameters', must be an [hashtable] or [DbParameter[]]"
				}
			}				
			
			Write-Verbose ("Executing Command ($executeType): '{0}'" -f $cmd.CommandText)		
		
			if ($executeType -eq "NonQuery") 
			{			
				$result = $cmd.ExecuteNonQuery()
				Write-Output $result
			}
			elseif ($executeType -eq "Scalar") 
			{
				$result = $cmd.ExecuteScalar()				
				Write-Output $result
			}
			elseif ($executeType -eq "Reader") 
			{
				$reader = $cmd.ExecuteReader()				
				Write-Output (,$reader)
			}
			elseif ($executeType -eq "Query") 
			{								
				$reader = $cmd.ExecuteReader()
				
				while($reader.Read())
				{
					$hashRow = @{}
					
					for ($fieldOrdinal = 0; $fieldOrdinal -lt $reader.FieldCount; $fieldOrdinal++)
                    {
                        $key = $reader.GetName($fieldOrdinal)
						$value = $reader.GetValue($fieldOrdinal)					
						if ($value -is [DBNull]) { $value = $null }
						
						$hashRow.Add($key, $value);                        
                    }
					
					Write-Output $hashRow
				}
				
				$reader.Close()
				$reader.Dispose()
			}
			elseif ($executeType -eq "QueryAsDataSet" -or $executeType -eq "QueryAsTable") 
			{
				# Já pode ter sido instanciado antes
				
				if ($providerFactory -eq $null)
				{
					$providerName = $connection.GetType().Namespace
					$providerFactory = [System.Data.Common.DBProviderFactories]::GetFactory($providerName)
				}
				
				try
				{
					$adapter = $providerFactory.CreateDataAdapter()
					
					$adapter.SelectCommand = $cmd
					
					$dataset = New-Object System.Data.DataSet
					
					$adapter.Fill($dataSet) | Out-Null					
					
					if ($executeType -eq "QueryAsTable")
					{
						Write-Output (,$dataset.Tables[0])	
					}
					else
					{
						Write-Output (,$dataset)	
					}					
				}
				finally
				{	
					if ($adapter)
					{
						$adapter.Dispose()
					}
				}								
			} 
			else
			{
				throw "Invalid executionType $executeType"
			}
			
			if ($cmd)
			{						
				$cmd.Dispose()
			}
		}
	}
	finally
	{
		# Only Dispose the connection if its a connection string parameter set
		
		if ($PsCmdlet.ParameterSetName -eq "connStr" -and $connection -ne $null -and $executeType -ne "Reader")
		{
			Write-Verbose ("Closing Connection to: '{0}'" -f $connection.ConnectionString)
			
			$connection.Close()
			
			$connection.Dispose()
			
			$connection = $null
		}
	}	
}

function Invoke-SQLQuery{
<#
.SYNOPSIS
    Invokes a SQL select query
		
 .EXAMPLE
        Invoke-SQLQuery -connectionString "<connStr>" -commandText "select * from [table]"
		Executes the SQL select command and returns to the pipeline a hashtable representing the row columns

#>
	[CmdletBinding(DefaultParameterSetName = "connStr")]
	param(						
		[Parameter(Mandatory=$false, ParameterSetName = "connStr")] [string] $providerName = "System.Data.SqlClient",
		[Parameter(Mandatory=$true, ParameterSetName = "connStr")] [string] $connectionString,
		[Parameter(Mandatory=$true, ParameterSetName = "conn")] [System.Data.Common.DbConnection] $connection,	
		[Parameter(Mandatory=$false, ParameterSetName = "conn")] [System.Data.SqlClient.SqlTransaction] $transaction,
		[Parameter(Mandatory=$true)] [string] $query,		
		$parameters = $null,
		[int] $commandTimeout = 300
		)
	
	if ($PsCmdlet.ParameterSetName -eq "connStr")
	{
		Invoke-SQLCommand -executeType "Query" -connectionString $sourceConnStr -providerName $providerName -commandText $query -parameters $parameters -commandTimeout $commandTimeout
	}
	else
	{
		Invoke-SQLCommand -executeType "Query" -connection $connection -transaction $transaction -commandText $query -parameters $parameters -commandTimeout $commandTimeout
	}	 
		
}

#Region Bulk Copy

Function Invoke-SQLBulkCopy{  
<#
.SYNOPSIS
    Inserts data in bulk to the specified SQL Server table
		
 .EXAMPLE
        Invoke-SQLBulkCopy -connectionString "<connStr>" -data "<source DataTable>" -tableName "<destination table>" -batchSize 1000 -Verbose        

#>
	[CmdletBinding(DefaultParameterSetName = "connStr")]
	param(		
		[Parameter(Mandatory=$true, ParameterSetName = "connStr")] [string] $connectionString,
		[Parameter(Mandatory=$true, ParameterSetName = "conn")] [System.Data.SqlClient.SqlConnection] $connection,
		[Parameter(Mandatory=$false, ParameterSetName = "conn")] [System.Data.SqlClient.SqlTransaction] $transaction,		
		[Parameter(Mandatory=$true)] $data,
		[Parameter(Mandatory=$true)] [string] $tableName,
		[Parameter(Mandatory=$false)] [hashtable]$columnMappings = $null,
		[Parameter(Mandatory=$false)] [int]$batchSize = 1000
	)
	
	try
	{					
		if ($PsCmdlet.ParameterSetName -eq "connStr")
		{
			$connection = Get-SQLConnection -connectionString $connectionString -providerName "System.Data.SqlClient" -open			
		}	    	    				
		
		if ($data -is [hashtable])
		{									
			if ($data["reader"] -is [System.Data.IDataReader])
			{
				$data = $data["reader"]								
			}	
			else
			{
				throw "Invalid type for '-data', must be a HashTable with 'reader' property of type DbReader"
			}
		}
		
		$bulk = New-Object System.Data.SqlClient.SqlBulkCopy($connection, [System.Data.SqlClient.SqlBulkCopyOptions]::TableLock, $transaction)  				
		
		$bulk.DestinationTableName = $tableName		
		
		Write-Verbose "SQLBulkCopy started for '$($bulk.DestinationTableName)'"
		
		if ($columnMappings -ne $null)
		{
			$columnMappings.GetEnumerator() |% {
					$bulk.ColumnMappings.Add($_.Key, $_.Value) | Out-Null
				}
		}
		else
		{
			# Define the columnmappings
			if ($data -is [System.Data.DataTable])
			{																			
				$data.Columns |%{
					$bulk.ColumnMappings.Add($_.ColumnName, $_.ColumnName) | Out-Null
				}			
			}			
		}
		
		$bulk.BatchSize = $batchSize
		$bulk.NotifyAfter = $batchSize
		
		$bulk.Add_SQlRowscopied({
			Write-Verbose "$($args[1].RowsCopied) rows copied."
			})
					
	    $bulk.WriteToServer($data)    	
		
		$bulk.Close()
		
		Write-Verbose "SQLBulkCopy finished for '$($bulk.DestinationTableName)'"
	}	
	finally
	{	
		if ($PsCmdlet.ParameterSetName -eq "connStr" -and $connection -ne $null)
		{
			Write-Verbose ("Closing Connection to: '{0}'" -f $connection.ConnectionString)
			
			$connection.Close()
			$connection.Dispose()
			$connection = $null
		}
	}	   
}

function New-SQLTable{
<#
.SYNOPSIS
    Creates a new SQL Server table for the specified schema		

#>
    [CmdletBinding(DefaultParameterSetName = "connStr")]
	param(						
		[Parameter(Mandatory=$true, ParameterSetName = "connStr")] [string] $connectionString,
		[Parameter(Mandatory=$true, ParameterSetName = "conn")] [System.Data.SqlClient.SqlConnection] $connection,
		[Parameter(Mandatory=$false, ParameterSetName = "conn")] [System.Data.SqlClient.SqlTransaction] $transaction,		   
		[Parameter(Mandatory=$true)] $data,
		[Parameter(Mandatory=$true)] [string] $tableName,
		[Parameter(Mandatory=$false)] [string] $customColumns,
		[Parameter(Mandatory=$false)] [string] $identityColumnName,
		[Switch] $force
		)
			 										
    $strcolumns = "";
	
	if ($data -is [System.Data.DataTable])
	{
		#https://msdn.microsoft.com/en-us/library/cc716729%28v=vs.110%29.aspx
	    foreach($obj in $data.Columns)
	    {
			$sqlType = Convert-DotNetTypeToSQLType $obj.DataType.ToString()
			
			$strcolumns = $strcolumns +",[$obj] $sqlType NULL" + [System.Environment]::NewLine
	    }
	}	
	else
	{		
		if ($data -is [hashtable])
		{
			if ($data["reader"] -is [System.Data.IDataReader])
			{
				$data = $data["reader"]		
				
				$schemaTable = $data.GetSchemaTable()
			
			    foreach($col in $schemaTable)
			    {					
					$colName = $col.ColumnName
					$sqlType = Convert-DotNetTypeToSQLType $col.DataType.ToString() $col.ColumnSize $col.NumericPrecision $col.NumericScale $col.DataTypeName
					
					$strcolumns = $strcolumns +",[$colName] $sqlType NULL" + [System.Environment]::NewLine
			    }
			}	
			else
			{
				throw "Invalid type for '-data', must be a HashTable with 'reader' property of type DbReader"
			}			
		}
		else
		{
			throw "Invalid type for '-data', must be an [System.Data.DataTable] or [HashTable] (with a DBDataReader)"
		}				
	}

    $strcolumns = $strcolumns.TrimStart(",")
	
	if (-not [string]::IsNullOrEmpty($identityColumnName))
	{
		$strcolumns += ", [$identityColumnName] [int] IDENTITY(1,1) NOT NULL"
	}
	
	if (-not [string]::IsNullOrEmpty($customColumns))
	{
		$strcolumns += ", " + $customColumns
	}
	
    $commandText = "
	IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'$tableName') AND type in (N'U'))
	BEGIN
		CREATE TABLE $tableName
        (
        	$strcolumns
        );
	END					
	"
	
	if ($force)
	{
		$commandText = "
		IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'$tableName') AND type in (N'U'))
		BEGIN
			drop table $tableName
		END
		;		
		" + $commandText
	}
	
	if ($PsCmdlet.ParameterSetName -eq "connStr")
	{
		Invoke-SQLCommand -connectionString $connectionString -providerName "System.Data.SqlClient" -commandText $commandText -executeType "NonQuery" | Out-Null
	}
	else
	{
		Invoke-SQLCommand -connection $connection -transaction $transaction -commandText $commandText -executeType "NonQuery" | Out-Null
	}				
}

function Test-SQLTableExists{
<#
.SYNOPSIS
    Tests if the SQL Table Exists		

#>
    [CmdletBinding(DefaultParameterSetName = "connStr")]
	param(						
		[Parameter(Mandatory=$true, ParameterSetName = "connStr")] [string] $connectionString,
		[Parameter(Mandatory=$true, ParameterSetName = "conn")] [System.Data.SqlClient.SqlConnection] $connection,
		[Parameter(Mandatory=$false, ParameterSetName = "conn")] [System.Data.SqlClient.SqlTransaction] $transaction,		   		
		[Parameter(Mandatory=$true)] [string] $tableName		
		)
			 										   	
    $commandText = "
	IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'$tableName') AND type in (N'U'))
	BEGIN
		select cast(1 as bit)
	END
	ELSE
	BEGIN
		select cast(0 as bit)
	END
	"
	
	if ($PsCmdlet.ParameterSetName -eq "connStr")
	{
		$result = Invoke-SQLCommand -connectionString $connectionString -providerName "System.Data.SqlClient" -commandText $commandText -executeType "Scalar"
	}
	else
	{
		$result = Invoke-SQLCommand -connection $connection -transaction $transaction -commandText $commandText -executeType "Scalar"
	}				
	
	Write-Output $result
}

#endregion

#region Private Methods

function Convert-DotNetTypeToSQLType ($typeStr, $size, $numericPrecision, $numericScale, $dataTypeName){
	
	switch ($typeStr)
	{
		"System.Double" {
			return "float"
		}
		"System.Boolean" {
			return "bit"
		}
		"System.String"{
			if (-not [string]::IsNullOrEmpty($dataTypeName))
			{
				return "$dataTypeName($size)"
			}
			
			if ($size -ne $null)
			{
				return "nvarchar($size)"
			}
			else
			{
				return "nvarchar(max)"
			}
		}
		"System.Decimal"{
			# Scale zero default to int
			if ($numericScale -eq 0)
			{
				return "int"
			}
			
			if ($dataTypeName -like "*money")
			{
				return $dataTypeName
			}
			
			if ($numericScale -ne $null -and $numericScale -ne 255)
			{
				return "decimal($numericPrecision, $numericScale)"
			}
			
			return "decimal(38,4)"
		}
		"System.Byte"{
			return "tinyint"
		}
		"System.Int16"{
			return "smallint"
		}
		"System.Int32"{
			return "int"
		}	
		"System.Int64"{
			return "bigint"
		}
		"System.DateTime"{
			return "datetime2(0)"
		}
		"System.Byte[]"{
			return "varbinary(max)"
		}
		"System.Xml.XmlDocument"{
			return "xml"
		}
		default{
			return "nvarchar(MAX)"
		}
	}	
}


#endregion

Export-ModuleMember -Function @("Get-SQLConnection", "Invoke-SQLCommand", "Invoke-SQLQuery", "New-SQLTable", "Test-SQLTableExists", "Invoke-SQLBulkCopy")