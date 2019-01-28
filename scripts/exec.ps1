param(
 [string]
 $gatewayKey,
 [Parameter(Mandatory=$true)]$VSTSAccount,
[Parameter(Mandatory=$true)]$PersonalAccessToken,
[Parameter(Mandatory=$true)]$AgentName,
[Parameter(Mandatory=$true)]$PoolName,
[Parameter(Mandatory=$true)]$runAsAutoLogon,
[Parameter(Mandatory=$false)]$vmAdminUserName,
[Parameter(Mandatory=$false)]$vmAdminPassword
)

# init log setting
$logLoc = "$env:SystemDrive\WindowsAzure\Logs\Plugins\Microsoft.Compute.CustomScriptExtension\"
if (! (Test-Path($logLoc)))
{
    New-Item -path $logLoc -type directory -Force
}
$logPath = "$logLoc\tracelog.log"
"Start to excute gatewayInstall.ps1. `n" | Out-File $logPath

function Now-Value()
{
    return (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
}

function Throw-Error([string] $msg)
{
	try 
	{
		throw $msg
	} 
	catch 
	{
		$stack = $_.ScriptStackTrace
		Trace-Log "DMDTTP is failed: $msg`nStack:`n$stack"
	}

	throw $msg
}

function Trace-Log([string] $msg)
{
    $now = Now-Value
    try
    {
        "${now} $msg`n" | Out-File $logPath -Append
    }
    catch
    {
        #ignore any exception during trace
    }

}

function Run-Process([string] $process, [string] $arguments)
{
	Trace-Log "Run-Process: $process $arguments"
	
	$errorFile = "$env:tmp\tmp$pid.err"
	$outFile = "$env:tmp\tmp$pid.out"
	"" | Out-File $outFile
	"" | Out-File $errorFile	

	$errVariable = ""

	if ([string]::IsNullOrEmpty($arguments))
	{
		$proc = Start-Process -FilePath $process -Wait -Passthru -NoNewWindow `
			-RedirectStandardError $errorFile -RedirectStandardOutput $outFile -ErrorVariable errVariable
	}
	else
	{
		$proc = Start-Process -FilePath $process -ArgumentList $arguments -Wait -Passthru -NoNewWindow `
			-RedirectStandardError $errorFile -RedirectStandardOutput $outFile -ErrorVariable errVariable
	}
	
	$errContent = [string] (Get-Content -Path $errorFile -Delimiter "!!!DoesNotExist!!!")
	$outContent = [string] (Get-Content -Path $outFile -Delimiter "!!!DoesNotExist!!!")

	Remove-Item $errorFile
	Remove-Item $outFile

	if($proc.ExitCode -ne 0 -or $errVariable -ne "")
	{		
		Throw-Error "Failed to run process: exitCode=$($proc.ExitCode), errVariable=$errVariable, errContent=$errContent, outContent=$outContent."
	}

	Trace-Log "Run-Process: ExitCode=$($proc.ExitCode), output=$outContent"

	if ([string]::IsNullOrEmpty($outContent))
	{
		return $outContent
	}

	return $outContent.Trim()
}

function Download-Gateway([string] $url, [string] $gwPath)
{
    try
    {
        $ErrorActionPreference = "Stop";
        $client = New-Object System.Net.WebClient
        $client.DownloadFile($url, $gwPath)
        Trace-Log "Download gateway successfully. Gateway loc: $gwPath"
    }
    catch
    {
        Trace-Log "Fail to download gateway msi"
        Trace-Log $_.Exception.ToString()
        throw
    }
}

function Install-Gateway([string] $gwPath)
{
	if ([string]::IsNullOrEmpty($gwPath))
    {
		Throw-Error "Gateway path is not specified"
    }

	if (!(Test-Path -Path $gwPath))
	{
		Throw-Error "Invalid gateway path: $gwPath"
	}
	
	Trace-Log "Start Gateway installation"
	Run-Process "msiexec.exe" "/i gateway.msi INSTALLTYPE=AzureTemplate /quiet /norestart"		
	
	Start-Sleep -Seconds 30	

	Trace-Log "Installation of gateway is successful"
}

function Get-RegistryProperty([string] $keyPath, [string] $property)
{
	Trace-Log "Get-RegistryProperty: Get $property from $keyPath"
	if (! (Test-Path $keyPath))
	{
		Trace-Log "Get-RegistryProperty: $keyPath does not exist"
	}

	$keyReg = Get-Item $keyPath
	if (! ($keyReg.Property -contains $property))
	{
		Trace-Log "Get-RegistryProperty: $property does not exist"
		return ""
	}

	return $keyReg.GetValue($property)
}

function Get-InstalledFilePath()
{
	$filePath = Get-RegistryProperty "hklm:\Software\Microsoft\DataTransfer\DataManagementGateway\ConfigurationManager" "DiacmdPath"
	if ([string]::IsNullOrEmpty($filePath))
	{
		Throw-Error "Get-InstalledFilePath: Cannot find installed File Path"
	}
    Trace-Log "Gateway installation file: $filePath"

	return $filePath
}

function Register-Gateway([string] $instanceKey)
{
    Trace-Log "Register Agent"
	$filePath = Get-InstalledFilePath
	Run-Process $filePath "-era 8060"
	Run-Process $filePath "-k $instanceKey"
    Trace-Log "Agent registration is successful!"
}

function PrepMachineForAutologon () {
    # Create a PS session for the user to trigger the creation of the registry entries required for autologon
    Trace-Log "Prepping machine for auto logon"
    $computerName = "localhost"
    $password = ConvertTo-SecureString $vmAdminPassword -AsPlainText -Force
    if ($vmAdminUserName.Split("\").Count -eq 2)
    {
      $domain = $vmAdminUserName.Split("\")[0]
      $userName = $vmAdminUserName.Split('\')[1]
    }
    else
    {
      $domain = $Env:ComputerName
      $userName = $vmAdminUserName
      Trace-Log "Username constructed to use for creating a PSSession: $domain\\$userName"
    }
   
    $credentials = New-Object System.Management.Automation.PSCredential("$domain\\$userName", $password)
    Enter-PSSession -ComputerName $computerName -Credential $credentials
    Exit-PSSession
  
    $ErrorActionPreference = "stop"
  
    try
    {
      # Check if the HKU drive already exists
      Get-PSDrive -PSProvider Registry -Name HKU | Out-Null
      $canCheckRegistry = $true
    }
    catch [System.Management.Automation.DriveNotFoundException]
    {
      try 
      {
        # Create the HKU drive
        New-PSDrive -PSProvider Registry -Name HKU -Root HKEY_USERS | Out-Null
        $canCheckRegistry = $true
      }
      catch 
      {
        # Ignore the failure to create the drive and go ahead with trying to set the agent up
        Trace-Log "Moving ahead with agent setup as the script failed to create HKU drive necessary for checking if the registry entry for the user's SId exists.\n$_"
      }
    }
  
    # 120 seconds timeout
    $timeout = 120 
  
    # Check if the registry key required for enabling autologon is present on the machine, if not wait for 120 seconds in case the user profile is still getting created
    while ($timeout -ge 0 -and $canCheckRegistry)
    {
      $objUser = New-Object System.Security.Principal.NTAccount($vmAdminUserName)
      $securityId = $objUser.Translate([System.Security.Principal.SecurityIdentifier])
      $securityId = $securityId.Value
  
      if (Test-Path "HKU:\\$securityId")
      {
        if (!(Test-Path "HKU:\\$securityId\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Run"))
        {
          New-Item -Path "HKU:\\$securityId\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Run" -Force
          Trace-Log "Created the registry entry path required to enable autologon."
        }
        
        break
      }
      else
      {
        $timeout -= 10
        Start-Sleep(10)
      }
    }
  
    if ($timeout -lt 0)
    {
      Trace-Log "Failed to find the registry entry for the SId of the user, this is required to enable autologon. Trying to start the agent anyway."
    }
}

Trace-Log "Log file: $logLoc"
$uri = "https://go.microsoft.com/fwlink/?linkid=839822"
Trace-Log "Gateway download fw link: $uri"
$gwPath= "$PWD\gateway.msi"
Trace-Log "Gateway download location: $gwPath"


Download-Gateway $uri $gwPath
Install-Gateway $gwPath

Register-Gateway $gatewayKey


Trace-Log "InstallingBuildAgent"

$currentLocation = Split-Path -parent $MyInvocation.MyCommand.Definition
Trace-Log "Current folder: $currentLocation"

#Create a temporary directory where to download from VSTS the agent package (vsts-agent.zip) and then launch the configuration.
$agentTempFolderName = Join-Path $env:temp ([System.IO.Path]::GetRandomFileName())
New-Item -ItemType Directory -Force -Path $agentTempFolderName
Trace-Log "Temporary Agent download folder: $agentTempFolderName"

$serverUrl = "https://$VSTSAccount.visualstudio.com"
Trace-Log "Server URL: $serverUrl"

$retryCount = 3
$retries = 1
Trace-Log "Downloading Agent install files"
do
{
  try
  {
    Trace-Log "Trying to get download URL for latest VSTS agent release..."
    $latestReleaseDownloadUrl = "https://vstsagentpackage.azureedge.net/agent/2.126.0/vsts-agent-win-x64-2.126.0.zip"
    Invoke-WebRequest -Uri $latestReleaseDownloadUrl -Method Get -OutFile "$agentTempFolderName\agent.zip"
    Trace-Log "Downloaded agent successfully on attempt $retries"
    break
  }
  catch
  {
    $exceptionText = ($_ | Out-String).Trim()
    Trace-Log "Exception occured downloading agent: $exceptionText in try number $retries"
    $retries++
    Start-Sleep -Seconds 30 
  }
} 
while ($retries -le $retryCount)

# Construct the agent folder under the main (hardcoded) C: drive.
$agentInstallationPath = Join-Path "C:" $AgentName 
# Create the directory for this agent.
New-Item -ItemType Directory -Force -Path $agentInstallationPath 

# Create a folder for the build work
New-Item -ItemType Directory -Force -Path (Join-Path $agentInstallationPath $WorkFolder)

Trace-Log "Extracting the zip file for the agent"
$destShellFolder = (new-object -com shell.application).namespace("$agentInstallationPath")
$destShellFolder.CopyHere((new-object -com shell.application).namespace("$agentTempFolderName\agent.zip").Items(),16)

# Removing the ZoneIdentifier from files downloaded from the internet so the plugins can be loaded
# Don't recurse down _work or _diag, those files are not blocked and cause the process to take much longer
Trace-Log "Unblocking files"
Get-ChildItem -Recurse -Path $agentInstallationPath | Unblock-File | out-null

# Retrieve the path to the config.cmd file.
$agentConfigPath = [System.IO.Path]::Combine($agentInstallationPath, 'config.cmd')
Trace-Log "Agent Location = $agentConfigPath"
if (![System.IO.File]::Exists($agentConfigPath))
{
    Trace-Log "File not found: $agentConfigPath"
    return
}

# Call the agent with the configure command and all the options (this creates the settings file) without prompting
# the user or blocking the cmd execution

Trace-Log "Configuring agent"

# Set the current directory to the agent dedicated one previously created.
Push-Location -Path $agentInstallationPath

if ($runAsAutoLogon -ieq "true")
{
  PrepMachineForAutologon

  # Setup the agent with autologon enabled
  .\config.cmd --unattended --url $serverUrl --auth PAT --token $PersonalAccessToken --pool $PoolName --agent $AgentName --runAsAutoLogon --overwriteAutoLogon --windowslogonaccount $vmAdminUserName --windowslogonpassword $vmAdminPassword
}
else 
{
  # Setup the agent as a service
  .\config.cmd --unattended --url $serverUrl --auth PAT --token $PersonalAccessToken --pool $PoolName --agent $AgentName --runasservice
}

Pop-Location

Trace-Log "Agent install output: $LASTEXITCODE"