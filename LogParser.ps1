# v1.1
# added scan multiple paths

# Next...
# return error detail


Set-ExecutionPolicy Unrestricted

 <#
    .SYNOPSIS 
      Parses log files for WARN and ERROR counts
    .EXAMPLE
	  . .\logParserNew.ps1
    Start-Monitor -path C:\dev\Huddle\logs -cycles 30 -timeout 10 -purge 1
	Start-Monitor -env staging
	 
    Specify either a path or an env parameter, 
	env will read environment paths in the relevant text file
	and reads the logs returning a count of warnings or errors. 
	Use -timeout to repeat cycles and -purge to remove 
	existing log files (only works with -path)
  #>

function Start-Monitor {

Param(
   [ValidateScript({Test-Path $_ -PathType 'Container'})] 
   [string]$path,
   [string]$env,
   #[int]$hoursback,
   [int]$cycles,
   [int]$timeout,
   [bool]$purge
)
$maxCount = 100

	if (!$path)
	{	
		$currentDir = $PWD.Path
		$locations = Get-Content $currentDir\$env.txt
		foreach ($location in $locations) 
		{
			$path = $location		
			Get-Size
			Run-Scan $path
		}
	}	
	if ($path) 
	{
		Get-Size 
		Run-Scan $path
		}
	if ($purge)
	{
		$purgeresponse = Read-Host "`n" "Are you sure you want to purge " $path "y/n?"
		if ($purgeresponse -eq "y") 
		{
			Get-ChildItem -Path $path -Recurse -Force | Where-Object { !$_.PSIsContainer } | Remove-Item
		}
	}
}
Function Get-Size 
{
 	Write-Host "`n" "---Folder Size Report---"
	Get-ChildItem -Path $path -Directory -Recurse -EA 0 | Get-FolderSize | Sort-Object size -Descending
 	Write-Host "---------" "`n"
}
Function Get-FolderSize {

	Begin{
		$fso = New-Object -comobject Scripting.FileSystemObject
		}
	Process
	{
	    $folderpath = $input.fullname
	    $folder = $fso.GetFolder($folderpath)
	    $size = $folder.size
	    [PSCustomObject]@{'Folder Name' = $folderpath;'Size' = [math]::Round(($size / 1Mb),1)} 
	} 
}
function Monitor ([int]$count)
{
	if ($count -gt 0)
	{ 
		$bar = "■"
		for ($i = 2; $i -le $count; $i++)
		{
			if ($i -le $maxCount) { $bar = $bar + "■" }
		}
	}
	return $bar
}
function Run-Scan ($path) 
{			
		Get-ChildItem -Path $path -Recurse  | Where-Object {($_.Name -match ".log\b")} | % {
			
			$warns = (Get-Content $_.FullName | Select-String -Pattern "\bWARN.{1,115}" -CaseSensitive -AllMatches | % { $_.Matches})
			$errors = (Get-Content $_.FullName | Select-String -Pattern "\bERROR.{1,115}" -CaseSensitive -AllMatches | % { $_.Matches})
			[int]$warntotal = $warns.count	
			[int]$errortotal = $errors.count		
			if ($warntotal -gt 0 -or $errortotal -gt 0)
			{
				Write-Host "................................................................................................................."
				Write-Host "`n"  ">>> " $_.FullName "`n"	
				if ($warntotal -gt 0)
				{
					$wa = Monitor -count $warntotal 
					Write-Host -ForegroundColor Gray "Warnings: " $warntotal
					Write-Host -ForegroundColor "Yellow" $wa "`n"	
					$unique = $warns | sort | get-unique 
					Write-Host -ForegroundColor Gray "Unique: " $unique.Count
					Write-Host ""
					$unique | % {Write-Host -ForegroundColor "Yellow" $_.Value} 
					Write-Host ""
				}	
				if ($errortotal -gt 0)
				{	
					$wa = Monitor -count $errortotal
					Write-Host -ForegroundColor Gray "Errors: " $errortotal
					Write-Host -ForegroundColor "Red" $wa  "`n"	
					$unique = $errors | sort | get-unique 
					Write-Host -ForegroundColor Gray "Unique: " $unique.Count
					Write-Host ""
					$unique | % {Write-Host -ForegroundColor "Red" $_.Value} 
				}
			}
	}
	Write-Host "****************************************************************************************************""`n"
	 
	if ($cycles -gt 0) 
	{
	 	Write-Host "Remaining cycles: " $cycles "`n"
		if ($timeout -lt 1) 
		{
		 	$timeout = 60 
		 	Write-Host "No timeout entered, so the default is 60 secounds"
		}
		if ($timeout -gt 0) 
		{
			$tspan =  [timespan]::fromseconds($timeout)
			$sw = [diagnostics.stopwatch]::StartNew()
			while ($sw.elapsed -lt $tspan){ start-sleep -seconds 5 }
		    $cycles--
		    Start-Monitor -path $path -cycles $cycles -timeout $timeout
		 	}
		}
}

