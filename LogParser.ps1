
# LogParser v1.1

# References: http://weblogs.asp.net/whaggard/powershell-script-to-find-strings-and-highlight-them-in-the-output

# todo
# search term param
# group counts are still way too high :-(
# add purge list

Set-ExecutionPolicy Unrestricted

 <#
    .SYNOPSIS 
      Scans log files for WARN and ERROR messages
    .EXAMPLE
	> . .\logParser.ps1
	> Start-Monitor -env staging -minutesback 30
    > Start-Monitor -path D:\dev\Huddle\logs -minutesback 10
	 
    Run this script with either a path or environment param. 
	Env will scan environment paths from a local text file
	and return unique entries of warnings and errors for a
	configurable time period (minutesback param). 
	Use -purge to remove existing log files (only works with -path).
	-timeout and -cycles are depricated in this version.
  #>

function Start-Monitor {

Param
(
   [ValidateScript({Test-Path $_ -PathType Container})] 
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
$logval = '*LOG_VALUE*'
$splitDelim = ']'
$maxLogSize = 25MB
$maxLogBytes = 1500000

if ($path) 
{
    if(!(Test-Path $path -PathType Container))
    {
        Write-Host -foregroundcolour Red "Folder not found: $path"
    }
	else {
	Run-Scan 
	Write-Host -f Cyan "`n`n-----------------------------------------"
	Write-Host -f Cyan "Scanning..." $path "`n"
	}
	if ($purge)
{
	$purgeresponse = Read-Host "`n" "Are you sure you want to purge " $path "y/n?"
	if ($purgeresponse -eq "y") 
	{
		Get-ChildItem -Path $path -Recurse -Force | Where-Object { !$_.PSIsContainer } | Remove-Item -ErrorAction SilentlyContinue
	}
}
}
if ($env)
{	
	$currentDir = $PWD.Path
	$locations = Get-Content $currentDir\env\$env.txt
	foreach ($location in $locations) 
	{
	    if(!(Test-Path $location -PathType Container))
    	{
        	Write-Host -foregroundcolour Red "Folder not found: $location"
    	}
		else { 
		$path = $location
		Run-Scan
		Write-Host -f Cyan "`n`n-----------------------------------------"
		Write-Host -f Cyan "Scanning..." $path "`n"
		}
		if ($purge)
		{
			if(!(Test-Path $location -PathType Container))
			{
				Write-Host -foregroundcolour Red "Folder not found: $location"
			}
			else {
			$purgeresponse = Read-Host "`n" "Are you sure you want to purge " $path "y/n?"
				if ($purgeresponse -eq "y") 
				{
					Get-ChildItem -Path $path -Recurse -Force | Where-Object { !$_.PSIsContainer } | Remove-Item -ErrorAction SilentlyContinue
				}
			}
		}
	}
}	
} # start-monitor #
Function Run-Scan 
{
	$logPaths = Get-Logs $path
	Get-Size	
	$errorStrip = Write-Lines "ERRORS"
	Write-Host -f Red "`n$errorStrip`n`n"
	Scan $path $logPaths $errorPattern
	$warnStrip = Write-Lines "WARNS"
	Write-Host -f Yellow "`n$warnStrip`n`n"
	Scan $path $logPaths $warnPattern
}
function Write-Lines ($inputStr)
{
	$hosta = Get-Host
	$win = $hosta.ui.rawui.windowsize
	[int]$width = ($win.width / 2) - 8
	if ($width -gt 0)
	{ 
		$n = "-"
		for ($i = 0; $i -le $width; $i++){ $n = $n + "-" }
	} 
	[string]$text = "[ " + $n + " $inputStr " + $n + " ]"	
	return $text
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
	$logPaths = Gci -Path $path -Recurse  | ? {($_ -ne $null -and $_.Name -match "error.log\b" -and $_.LastWriteTime -gt $laterThan -and $_.length -lt $maxLogSize)}

	return $logPaths
}
function Filter-Size
{
	$bigFiles = Gci -Path $path -Recurse  | ? {($_ -ne $null -and $_.Name -match "error.log\b" -and $_.length -ge $maxLogBytes)}
	if ($bigFiles.count -gt 0) 
	{ 
		$initialColor = $Host.ui.rawui.ForegroundColor
		Write-Host -f Red "WARNING: The following files are too large to monitor"
		$bigFiles | sort length |
		ft -Property Fullname, @{ label = "Size(mb)"; 
	  	Expression = 
		{
			$Host.ui.rawui.ForegroundColor = "Gray"; 
			[int]$lengthmb = ([math]::Round(($_.length / 1Mb),1))
			if ($lengthmb -ge 15) { $Host.ui.rawui.ForegroundColor = "Gray"; $lengthmb }
		}
	} -Auto
	Write-Host "`n---"
	$Host.ui.rawui.ForegroundColor = $initialColor
	}
}
function Filter-String ([string]$text)
{
	return $text  -replace ($guid, $logval) -replace ('\d{5,}', $logval) -replace ('Job#\d+\D\d+', $logval) -replace ('# \d{3,}', $logval)
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
						[Array]$msgArr += [PSCustomObject]@{'date' = $($_ -split $splitDelim)[0];'message' = $($_ -split $splitDelim)[1]}
					}											
				}
			}	
		if ($verbose) {$msgArr | % { Write-Host -f Green ("{0}]{1}" -f $_.Date, $_.Message) }
		}
		else 
		{	
		if ($msgArr -ne $null)
		{
			$filteredArr = $msgArr | Group-Object Message | % { $_.Group | sort Date | Select -Last 1 }
			
			[array]$messageGroupArr = @()			
			$msgArr | Group-Object Message | % { $messageGroupArr += $_.count }			
			$messageGroup = $msgArr | Group-Object Message | % { $_.count }			
			if ($messageGroup.length -gt 0){
				$xMsg = 0
				foreach ($groupCount in $messageGroupArr){ 
					$filteredArr | % `
					{ 	
						Write-Host -f Green ("{0}]{1}" -f $_.Date, $_.Message)
						if ($groupCount -gt 1 -and $groupCount -lt 5) { Write-Host -f Cyan "[$groupCount similar]"; $xMsg++ }
						if ($groupCount -ge 5 -and $groupCount -lt 15) { Write-Host -f Yellow "[$groupCount similar]"; $xMsg++ }
						if ($groupCount -ge 15) { Write-Host -f Red "[$groupCount similar]"; $xMsg++ }
					}
				}
				if ($xMsg -gt 0) { Write-Host -f Cyan ("`n[{0}{1}]`n" -f $xMsg, " message types with multiple entries") }
				}
			}
		  }		  
		}
		if ($msgArr -ne $null){$msgArr.clear()}
	}
}



