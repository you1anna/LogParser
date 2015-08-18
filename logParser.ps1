
# v1.0.2
# added multiple paths

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
	and recurses through the logs folder
	returning a count of warnings or errors. 
	Use -timeout to repeat cycles and -purge to remove 
	existing log files (only works with -path)
  #>

function Start-Monitor {

Param(
   [ValidateScript({Test-Path $_ -PathType 'Container'})] 
   [string]$path,
   [string]$env,
   [int]$cycles,
   [int]$timeout,
   [bool]$purge
)
$maxCount = 100

if ($purge)
{
	$purgeresponse = Read-Host "`n" "Are you sure you want to purge " $path "y/n?"
	if ($purgeresponse -eq "y") 
	{
		Get-ChildItem -Path $path -Recurse -Force | Where-Object { !$_.PSIsContainer } | Remove-Item
	}
}	
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
}
Function Get-Size 
{
 	Write-Host "`n" "---Folder Size Report---"
	Get-ChildItem -Path $path -Directory -Recurse -EA 0 | Get-FolderSize | Sort-Object size -Descending
 	Write-Host "---------" "`n"
}
Function Get-FolderSize {

BEGIN{$fso = New-Object -comobject Scripting.FileSystemObject}
PROCESS{
    	$path = $input.fullname
    	$folder = $fso.GetFolder($path)
    	$size = $folder.size
    	[PSCustomObject]@{'Folder Name' = $path;'Size' = [math]::Round(($size / 1Mb),1)} 
		} 
}
function Monitor ([int]$count, $level)
{
	if ($count -gt 0)
	{ 
		$d = "-"
		for ($i = 2; $i -le $count; $i++)
		{
			if ($i -le $maxCount) { $d = $d + "-" }
		}
	}
	return $d
}
function Run-Scan {

		Get-ChildItem -Path $path -Recurse  | Where-Object {$_.Name -match ".log\b"} | ForEach-Object {
		$errors = (Get-Content $_.FullName | Select-String -Pattern "] ERROR" -CaseSensitive -AllMatches | % { $_.Matches}).count
	    $warns = (Get-Content $_.FullName | Select-String -Pattern "] WARN" -CaseSensitive -AllMatches | % { $_.Matches}).count
		if ($errors -gt 0)
		{	
			Write-Host  ">>> " $_.FullName "`n"
			$er = Monitor -count $errors -level "ERROR"
			Write-Host -ForegroundColor "Red" "ERROR: " $errors 
			Write-Host -ForegroundColor "Red" $er
		}
		if ($warns -gt 0)
		{
			Write-Host  ">>> " $_.FullName "`n"
			$wa = Monitor -count $warns -level "WARN"
			Write-Host -ForegroundColor "Yellow" "WARNS: " $warns
			Write-Host -ForegroundColor "Yellow" $wa
		    Write-Host ""
		}
	}
	Write-Host "****************************************************************************************************""`n"
	 
	if ($cycles -gt 0) {
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

