
# LogParser v1.1 by Robin Miklinski

# group count incorrect /# with multiple entries
# move following files size'' to single call - and fix?
# filter-size needs fixing
#toolarge files in red

Set-ExecutionPolicy Unrestricted

 <#
    .SYNOPSIS 
      Scans log files for WARN and ERROR messages
    .EXAMPLE
	> . .\logParserNew.ps1
	> Start-Monitor -env staging -minutesback 30
    > Start-Monitor -path D:\dev\Huddle\logs -purge 10
	 
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
$lv = '*LOG_VALUE*'
$splitDelim = ']'
$maxLogSize = 15MB

if ($path) 
{
    if(!(Test-Path $path -PathType Container))
    {
        throw "Folder not found: $path"
    }
	else { Run-Scan }
}
if ($env)
{	
	$currentDir = $PWD.Path
	$locations = Get-Content $currentDir\env\$env.txt
	foreach ($location in $locations) 
	{
	    if(!(Test-Path $location -PathType Container))
    	{
        	Write-Host "Folder not found: $location"
    	}
		else { 
			$path = $location
			Run-Scan
			Write-Host -f Cyan "`n`n-----------------------------------------"
			Write-Host -f Cyan "Scanning..." $path "`n"}
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
	Write-Host -f White -b Red "`n[ ------- ERRORS ------- ]`n`n"
	Scan $path $logPaths $errorPattern
	Write-Host -f Black -b Yellow "`n[ ------- WARNS ------- ]`n`n"
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
	$logPaths = Gci -Path $path -Recurse  | ? {($_ -ne $null -and $_.Name -match "-error.log\b" -and $_.LastWriteTime -gt $laterThan -and $_.length -lt $maxLogSize)}

	return $logPaths
}
function Filter-Size
{
	$logs = Get-Logs $path
	if ($logs.count -gt 0) 
	{ 
		Write-Host -f Gray "The following files are too large to monitor:"
#		$logs | sort length | ft -Property fullname, @{label = "Size" ; Expression = {$Host.ui.rawui.ForegroundColor = White; $_.length}} -auto
#		$logs | sort length | ft -Property fullname, @{'Fullname' = $_.name; 'Size' = {$Host.ui.rawui.ForegroundColor = Red; [math]::Round((length / 1Mb),1)}}
#							 ft ProcessName, @{Label="TotalRunningTime"; Expression={$_.StartTime}}
		$logs | sort length | ft -Property fullname, @{
														label = "Size(MB)"; 
													  	Expression = 
														{
															$Host.ui.rawui.ForegroundColor = "red"; 
															[math]::Round(($_.length / 1Mb),1)
														}
													  } -AutoSize
		
							# ft -Property fullname, length -auto 
							# ft -Property name, @{label = "alert" ; Expression = { $Host.ui.rawui.ForegroundColor = "cyan" ; $_.length }
		Write-Host -f Gray  "`n---"
		$Host.ui.rawui.ForegroundColor = "white"
	}
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
						[Array]$msgArr += [PSCustomObject]@{'date' = $($_ -split $splitDelim)[0];'message' = $($_ -split $splitDelim)[1]}
					}											
				}
			}	
		if ($verbose) {$msgArr | % { Write-Host -f Green ("{0}]{1}" -f $_.Date, $_.Message) }
		}
		else 
		{			
			$filteredArr = $msgArr | Group-Object Message | % { $_.Group | sort Date | Select -Last 1 }
			
			[array]$messageGroupArr = @()			
			$msgArr | Group-Object Message | % { $messageGroupArr += $_.count }			
			$messageGroup = $msgArr | Group-Object Message | % { $_.count }			
			if ($messageGroup.length -gt 0){
				if ($filteredArr.length -gt 0) { Write-Host -f Cyan ("`n[{0}{1}]`n" -f $filteredArr.length, " message types with multiple entries") }
				foreach ($groupCount in $messageGroupArr){ 
					$filteredArr | % `
					{ 	
						Write-Host -f Green ("{0}]{1}" -f $_.Date, $_.Message) 
						if ($groupCount -gt 1) { Write-Host -f Cyan "[$groupCount similar]" }
					}
				}
			}
		  }
		}
	}
}





