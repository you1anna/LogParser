
# LogParser v1.1 by Robin Miklinski

# replace stuff like user=2783682?
# filter large files
# group count incorrect
# size filter getting wrong logs
# move following files size'' to single call - and fix?

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
   [bool]$purge,
   [bool]$verbose,
   [bool]$filter
)

$year = (get-date).year
$laterThan = [System.DateTime]::UtcNow.AddMinutes($minutesback * -1)
$warnPattern = ".*WARN.*\s(?!$year).*[\s\D]*"
$errorPattern = ".*ERROR.*\s(?!$year).*[\s\D]*"
$guid = "[a-fA-F0-9]{8}-([a-fA-F0-9]{4}-){3}[a-fA-F0-9]{12}"
$lv = '*LOG_VALUE*'
$splitDelim = ']'
$maxLogSize = 15MB

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
	Write-Host -f Red "`n[ ----- ERRORS ----- ]`n`n"
	Scan $path $logPaths $errorPattern
	Write-Host -f Yellow "`n[ ----- WARNS ----- ]`n`n"
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
	Begin {$fso = New-Object -comobject Scripting.FileSystemObject}
	Process{
	    $folderpath = $input.FullName
	    $folder = $fso.GetFolder($folderpath)
	    $size = $folder.size
	    [PSCustomObject]@{'Folder Name' = $folderpath;'Size' = [math]::Round(($size / 1Mb),1)} 
	} 
}
function Get-Logs ($path)
{		
	$logPaths = Gci -Path $path -Recurse  | ?{($_.Name -match "-error.log\b" -and $_.LastWriteTime -gt $laterThan -and $_.length -lt $maxLogSize)}

	return $logPaths
}
function Filter-Size
{
	if ($_ -ne $null) {Write-Host -f Gray "The following files are too large to monitor:"}
	Gci -Path $path -recurse | where {$_ -ne $null -and $_.Name -match "-error.log\b" -and $_.length -gt $maxLogSize} | sort length | ft -Property fullname, length -auto
}
function Filter-String ([string]$text)
{
	return $text -replace ('\d{6,}', $lv) -replace ('Job#\d+\D\d+', $lv) -replace ('# \d{3,}', $lv) -replace ($guid, $lv)
}
function Scan ($path, $logPaths, $pattern) 
{
	Filter-Size
	$logPaths | % `
	{
		if ($_ -ne $null) 
		{
			$file = $_.FullName
			Write-Host "`n[$file]"
		
			Get-Content $file | Select-String -Pattern $pattern -CaseSensitive -AllMatches | % `
			{ 	
				$regexDateTime = New-Object System.Text.RegularExpressions.Regex "((?:\d{4})-\d{2}-\d{2}\s\d{2}:\d{2}:\d{2}(,\d{3})?)"
				$matchDate = $regexDateTime.match($_)
				if($matchDate.success){
					$logLineDate = [System.DateTime]::ParseExact($matchDate, "yyyy-MM-dd HH:mm:ss,FFF", [System.Globalization.CultureInfo]::InvariantCulture)
					if ($logLineDate -gt $laterThan){
						if ($filter) { $_ = Filter-String $_ }
						[Array]$messageArr += [PSCustomObject]@{'date' = $($_ -split $splitDelim)[0];'message' = $($_ -split $splitDelim)[1]}
					}											
				}
			}
			
		if ($verbose) {$messageArr | % { Write-Host -f Green ("{0}]{1}" -f $_.Date, $_.Message) }
		}
		}
		else 
		{			
#			$x = $messageArr | Group-Object Message | % { $_.Group }
			$filteredArr = $messageArr | Group-Object Message | % { $_.Group | sort Date | Select -Last 1 }
			
			[array]$messageGroupArr = @()			
			$messageArr | Group-Object Message | % { $messageGroupArr += $_.count }			
			$messageGroup = $messageArr | Group-Object Message | % { $_.count }			
			if ($messageGroup.length -gt 0) 
			{
				Write-Host -f Cyan "`n["$filteredArr.length"messages with multiple entries]`n"
				foreach ($groupCount in $messageGroupArr) 
				{ 
					$filteredArr | % `
					{ 	
						Write-Host -f Green ("{0}]{1}" -f $_.Date, $_.Message) 
						if ($groupCount -gt 1) { Write-Host -f Cyan "[$groupCount]" }
					}
				}
			}
		}	
	}
}





