<# 

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
		[Parameter(Mandatory=$false)] [int]$batchSize = 10000
	)
	
	try
	{	
		if ($PsCmdlet.ParameterSetName -eq "connStr")
		{
			$connection = Get-SQLConnection -connectionString $connectionString -providerName "System.Data.SqlClient" -open			
		}	    	    		
		
		$bulk = New-Object System.Data.SqlClient.SqlBulkCopy($connection, [System.Data.SqlClient.SqlBulkCopyOptions]::TableLock, $transaction)  				
		
		$bulk.DestinationTableName = $tableName		
		
		Write-Verbose "SQLBulkCopy started for '$($bulk.DestinationTableName)'"
		
		if ($data -is [System.Data.DataTable])
		{
			Write-Verbose "Writing $($data.Rows.Count) rows"					
			
			# by default mapps all the datatable columns
			
			if ($columnMappings -eq $null)
			{
				$data.Columns |%{
					$bulk.ColumnMappings.Add($_.ColumnName, $_.ColumnName) | Out-Null
				}
			}
			else
			{
				$columnMappings.GetEnumerator() |% {
					$bulk.ColumnMappings.Add($_.Key, $_.Value) | Out-Null
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
    Invokes a SQLCommand of type: "Query", "QueryAsDataSet", "NonQuery", "Scalar", "Reader", "Schema"
		
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
		[ValidateSet("Query", "QueryAsDataSet", "NonQuery", "Scalar", "Reader", "Schema")] [string] $executeType = "Query",
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
					$parameters |% {
						$cmd.Parameters.Add($_) | Out-Null
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
				Write-Output $cmd.ExecuteNonQuery()
			}
			elseif ($executeType -eq "Scalar") 
			{
				Write-Output $cmd.ExecuteScalar()
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
			elseif ($executeType -eq "QueryAsDataSet") 
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

					Write-Output (,$dataset)	
				}
				finally
				{	
					if ($adapter -ne $null)
					{
						$adapter.Dispose()
					}
				}								
			} 
			else
			{
				throw "Invalid executionType $executeType"
			}
			
			$cmd.Dispose()
		}
	}
	finally
	{
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
		[Parameter(Mandatory=$true)] [System.Data.DataTable] $table,
		[Parameter(Mandatory=$true)] [string] $tableName,
		[Parameter(Mandatory=$true)] [string] $customColumns,
		[Switch] $force
		)
			 										
    $strcolumns = "";

    #https://msdn.microsoft.com/en-us/library/cc716729%28v=vs.110%29.aspx
    foreach($obj in $table.Columns)
    {
		$sqlType = Convert-DotNetTypeToSQLType $obj.DataType.ToString()
		
		$strcolumns = $strcolumns +",[$obj] $sqlType NULL" + [System.Environment]::NewLine
    }

    $strcolumns = $strcolumns.TrimStart(",")
	
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

#region Private Methods

function Convert-DotNetTypeToSQLType ($typeStr){
	
	$typesHash = @{ 
	"System.Double" = "float" 
	; "System.String" = "nvarchar(MAX)"
	; "System.Int32" = "int"
	; "System.Int16" = "smallint"
	; "System.Int64" = "bigint"
	; "System.Decimal" = "decimal(18,4)"
	; "System.Boolean" = "bit"
	; "System.DateTime" = "datetime2(0)"
	; "System.Byte[]" = "varbinary(max)"
	; "System.Xml.XmlDocument" = "xml"
	};
	
	if ($typesHash.ContainsKey($typeStr))
	{
		return $typesHash[$typeStr];
	}
	else
	{
		return "nvarchar(MAX)"
	}
}


#endregion

Export-ModuleMember -Function @("Invoke-SQLBulkCopy", "Get-SQLConnection", "Invoke-SQLCommand", "Invoke-SQLQuery", "New-SQLTable")