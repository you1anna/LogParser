
# LogParser v1.1 by Robin Miklinski

# replace stuff like user=2783682?

Set-ExecutionPolicy Unrestricted

 <#
    .SYNOPSIS 
      Parses log files for WARN and ERROR counts
    .EXAMPLE
	> . .\logParserNew.ps1
	> Start-Monitor -env staging -minutesback 6
    > Start-Monitor -path C:\dev\Huddle\logs -purge 10
	 
    Specify either a path or environment parameters, 
	env will read environment paths from a local text file
	and return unique entries of warnings and errors for a
	configurable time period (minutesback parameter). 
	Use -purge to remove existing log files (only works with -path).
	Note: -timeout and -cycles are depricated in this version.
  #>

function Start-Monitor {

Param
(
   [ValidateScript({Test-Path $_ -PathType 'Container'})] 
   [string]$path,
   [string]$env,
   [int]$minutesback,
   [bool]$purge
)

$messageArr = @()
$year = (get-date).year
$splitDelim = ']'
$warnPattern = ".*WARN.*\s(?!$year).*[\s\D]*"
$errorPattern = ".*ERROR.*\s(?!$year).*[\s\D]*"
$guid = "[a-fA-F0-9]{8}-([a-fA-F0-9]{4}-){3}[a-fA-F0-9]{12}"

if ($path) 
{
	Run-Scan
}
if ($env)
{	
	$currentDir = $PWD.Path
	$locations = Get-Content $currentDir\$env.txt
	foreach ($location in $locations) 
	{
		$path = $location
		Write-Host -f Cyan "`nScanning..." $path
		Run-Scan
	}
}	
if ($purge)
{
	$purgeresponse = Read-Host "`n" "Are you sure you want to purge " $path "y/n?"
	if ($purgeresponse -eq "y") 
	{
		Get-ChildItem -Path $path -Recurse -Force | Where-Object { !$_.PSIsContainer } | Remove-Item
	}
}
} # start-monitor #
Function Run-Scan 
{
	$logPaths = Get-Logs $path
	Get-Size
	Write-Host -f Red "`n --- ERRORS ---`n"
	Scan $path $logPaths $errorPattern
	Write-Host -f Yellow "`n--- WARNS ---`n"
	Scan $path $logPaths $warnPattern
}
Function Get-Size
{
 	Write-Host "`n" "---Folder Size Report---"
	Get-ChildItem -Path $path -Directory -Recurse -EA 0 | Get-FolderSize | Sort-Object size -Descending
 	Write-Host "---------" "`n"
}
Function Get-FolderSize 
{
	Begin 
	{
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
function Get-Logs ($path)
{	
	$laterThan = [System.DateTime]::UtcNow.AddMinutes($minutesback * -1)
	$logPaths = Gci -Path $path -Recurse  | ?{($_.Name -match ".log\b" -and $_.LastWriteTime -gt $laterThan)}
	
	return $logPaths
}
function Filter-String ([string]$text)
{
	
}
function Scan ($path, $logPaths, $pattern) 
{
	$logPaths | % `
	{ 
		$file = $_.FullName
		Write-Host "`n[$file]"
		Get-Content $file | Select-String -Pattern $pattern -CaseSensitive -AllMatches | % `
		{ 	
			$regexDateTime = New-Object System.Text.RegularExpressions.Regex "((?:\d{4})-\d{2}-\d{2}\s\d{2}:\d{2}:\d{2}(,\d{3})?)"
			$matchDate = $regexDateTime.match($_)
			if($matchDate.success)				
			{
				$loglinedate = [System.DateTime]::ParseExact($matchDate, "yyyy-MM-dd HH:mm:ss,FFF", [System.Globalization.CultureInfo]::InvariantCulture)
				if ($loglinedate -gt $laterThan)
				{
					if ($_ -match 'user=\d+') 
					{	
						$_ = $_ -replace 'user=\d+','user=...'
					}
					
					$d = $($_.toString().TrimStart() -split $splitDelim)[0]
					$m = $($_.toString().TrimStart() -split $splitDelim)[1]
					$messageArr += ,$d,$m
#					$messageArr += ,@($_.toString() -split $splitDelim)	
				}											
			}
		}
		Write-Host "A: " $messageArr
		Write-Host "[Count: " $messageArr.length"]`n`nUnique..."
		$messageAr | sort $m -Unique | foreach { Write-Host -f Green $d$m}
		
#		$messageArr | sort -Unique | foreach { Write-Host -f Green $_}
	}	
}





