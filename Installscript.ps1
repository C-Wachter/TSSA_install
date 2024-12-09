#Requires -Version 5.0

<#
.SYNOPSIS
Installs TSSA RSCD Agent on target

.DESCRIPTION
This script will install TSSA RSCD Agent provided in the package and configure it with the customer and account 
provided as parameters. It will also check if Visual C++ runtime is installed ($minimum_visual_c_runtime_version
contains the required version) and install the VC++ runtime module. if required.

.EXAMPLE
Installscript -Customer 'Kunde' -Account 'Administrator'

.NOTES
Minimum OS Architecture Supported: Windows Server 2016
Release Notes: Release 0.7 by Clemens Wachter (clemens.wachter@atos.net)
Version history
0.8 Replaced Parameter -User by -Customer -Account
0.7 Add Siemens special (Step 7)
0.6 Check if Port 4750 is listening
0.5 Added try/catch for error handling and logging
0.4 ACL settings
0.3 check and install VC++ if needed
0.2 Write-Logging function added
0.1 Initial version 

By using this script, you accept the following terms.
Ownership Rights: Atos Information Technology GmbH (Atos) owns and will continue to own all right, title, and interest in and to the script, including the copyright.
Atos is giving the customer a limited license to use the script in accordance with these legal terms.
Use Limitation: This script may only be used for your legitimate business purposes, and may not be shared with another party.
Republication Prohibition: Under no circumstances may this script be re-published in any script library or website belonging to or under the control of any other company or software provider. 
Warranty Disclaimer: The script is provided “as is” and “as available”, without warranty of any kind. Atos makes no promise or guarantee that the script will be free from defects or that it will meet your specific needs or expectations. 
Assumption of Risk: Your use of the script is at your own risk. You acknowledge that there are certain inherent risks in using the script, and you understand and assume each of those risks. 
Waiver and Release: You will not hold Atos responsible for any adverse or unintended consequences resulting from your use of the script, and you waive any legal or equitable rights or remedies you may have against Atos relating to your use of the script. 

.COMPONENT
Requires Atos Packageinstaller
#>


#Get Parameters $Customer and $Account from command line
Param (
    [Parameter(Mandatory = $true)]
    [String]$Customer   #Customer, Script will convert to first part of $tssa_connect_string in the form 'Customer_L3AdminX:*"
    ,
    [Parameter(Mandatory = $true)]
    [String]$Account     #Local Administrator, Script will convert to 2nd part of $tssa_connect_string in the form 'rw,map=Administrator'
)

#Define constants
$LogDateFormat = "%m/%d/%Y %H:%M:%S"
$tssa_install_log = "TSSA_RSCD.log"
$tssa_config_dir = "c:\windows\rsc"
$tssa_config_file = "users.local"
# Siemens special parameter
$tssa_secure_file = "secure"
$tssa_secure_backup = "secure.bak"
$cert_dir = "c:\Program Files\BMC Software\BladeLogic\RSCD\certs"
$certs = "bladmin", "root"
################################################################################
#Change new versions HERE!                                                     #
################################################################################
$visual_c_install_file = "VC_redist.x64.exe"
[System.Version]$Minimum_Visual_C_Runtime_Version = 14.32
$tssa_install_file = "RSCD242-WIN64.msi"
################################################################################

#Check environment variable %PINST_CACHE_PACKAGE_SOURCE%
if (!$env:PINST_CACHE_PACKAGE_SOURCE) {
    $path2executable = (Get-Location).Path
    }
else {
    $path2executable = $env:PINST_CACHE_PACKAGE_SOURCE
    }

#Define functions
Function Write-Logging {
    Param (
        [Parameter()]
            [ValidateSet("Information","Warning","Error","Debug","Verbose")]
            [String]$Loglevel = 'Information',
            [String]$Message
    )
Write-Output ("[{0}] {1}: {2}" -F (Get-Date -UFormat $LogDateFormat), $loglevel, $Message)
}

# Logischer Aufbau des Skripts
# 1. Prüfen ob und in welcher Version VC++ Runtime installiert ist
# 2. Wenn notwendig, installieren
# 3. Installation TSSA MSI-File /qn usw.
# 4. RSCD service stoppen
# 5. Berechtigungen auf C:\Windows\rsc prüfen und ggfs setzen
# 6. Änderungen an users.local (param -Customer -Account) und ggfs anderen Dateien
# 7. Sonderlocke Siemens
# 8. RSCD service starten
# 9. Status von Port 4750 prüfen

Write-Logging -Loglevel Information -Message "Installscript started."

#Step 1: Check VC++ Runtime
#Step 1.1: Find Installed Visual C++ Runtime 
$installed_SW = Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* | Select-Object DisplayName, DisplayVersion
$installed_Visual_C_Runtime = $installed_SW | Where-Object {$_.DisplayName -like 'Microsoft Visual C++*'} | Sort-Object -Property DisplayVersion -Descending | Select-Object -First 1

#Step 1.2: Check Installed Visual C++ Runtime version against required $Minimum_Visual_C_Runtime_Version
$install_VC = $false
switch ($installed_Visual_C_Runtime.Count) {
    0 { $install_VC = $true
        Write-Logging -Loglevel Warning -Message "No Visual C++ found. Going to install..."
    }
    1 { if ($installed_Visual_C_Runtime.DisplayVersion -lt $Minimum_Visual_C_Runtime_Version) {
            $install_VC = $true
            Write-Logging -Loglevel Warning -Message "Visual C++ Version insufficient. Going to install..."
            }
        else {
            Write-Logging -Loglevel Information -Message "Visual C++ version OK. Skipping installation."
            }
    }
}

#Step 2: Install Visual C++ Runtime if necessary
if ($install_VC -eq $true) {
    $executable = $visual_c_install_file
    $arguments = "/install /quiet"
    $command2execute = Join-Path -Path $path2executable -ChildPath $executable
    Write-Logging -Loglevel Information -Message "Starting Visual C++ Runtime Installation" 
    $returncode = (Start-Process -Wait -PassThru -FilePath $command2execute -WorkingDirectory $path2executable -ArgumentList $arguments).ExitCode
    if ($returncode -eq 0) {
        Write-Logging -Loglevel Information -Message "Visual C++ Runtime installed successfully"
    } 
    else {
        Write-Logging -Loglevel Error -Message "Error installing Visual C++ Runtime"
    }
}

#Step 3: Installing RSCD agent
$command2execute = "msiexec.exe"
$logfile = Join-Path -Path $env:temp -ChildPath $tssa_install_log
$arguments = "/i "+$tssa_install_file+" /quiet /qn /norestart REBOOT=ReallySuppress USE_ALL_TLS_VERSION=1 /l "+$logfile
$returncode = (Start-Process -Wait -PassThru -FilePath $command2execute -WorkingDirectory $path2executable -ArgumentList $arguments).ExitCode
if ($returncode -eq 0) {
    Write-Logging -Loglevel Information -Message "TSSA RSCD agent installed successfully"
} 
else {
    Write-Logging -Loglevel Error -Message "TSSA RSCD agent installation failed. Please check %TEMP%\TSSA_RSCD.log for further information."
}

#Step 4: stop RSCD service
try {
    Get-Service -Name "RSCDsvc" | Stop-Service -ErrorAction Stop
    Write-Logging -Loglevel Information -Message "RSCD service stopped"
}
catch {
    Write-Logging -Loglevel Error -Message "Could not stop RSCD service"
}

#Step 5: Get access rights to c:\windows\rsc\users.local
$change_acl = new-object System.Security.AccessControl.FileSystemAccessRule ("$env:USERDOMAIN\$env:USERNAME","Modify", "none", "none", "Allow")
#Step 5.1 S Add access for local user to directory 
$current_acl = get-acl -Path $tssa_config_dir
$current_acl.AddAccessRule($change_acl)
set-acl -AclObject $current_acl -Path $tssa_config_dir
#Step 5.2 S Add access for local user to users.local
$target_file = Join-Path -Path $tssa_config_dir -ChildPath $tssa_config_file
$current_acl = get-acl -Path $target_file
$current_acl.AddAccessRule($change_acl)
set-acl -AclObject $current_acl -Path $target_file

#Step 6: Edit users.local
if ($Customer -like "siteadmin*") {
    $tssa_connect_string=$Customer+":* rw,map="+$Account
} 
else {
    $tssa_connect_string=$Customer+"_L3AdminW:* rw,map="+$Account
}
Write-Logging -Loglevel Information -Message Created TSSA Connect String $tssa_connect_string

try {
    Add-Content -Path $target_file -Value $tssa_connect_string -ErrorAction Stop
    Write-Logging -Loglevel Information -Message "Added user to users.local"
}
catch {
    Write-Logging -Loglevel Error -Message "Could not edit users.local!"
}

#Step 7: Siemens special
If ($Customer -like "siteadmin*") {
    #Step 7.1: Get access rights to c:\windows\rsc\secure
    $target_file = Join-Path -Path $tssa_config_dir -ChildPath $tssa_secure_file
    $current_acl = get-acl -Path $target_file
    $current_acl.AddAccessRule($change_acl)
    set-acl -AclObject $current_acl -Path $target_file
    #Step 7.2: Rename secure -> secure.bak
    $backup_file = Join-Path -Path $tssa_config_dir -ChildPath $tssa_secure_backup
    Rename-Item -Path $target_file -NewName $backup_file
    #Step 7.3: Change \Windows\rsc\secure line starting with rscd: Replace encryption_only by encryption_and_auth
    try {
        (Get-Content -path $backup_file -Raw).replace('encryption_only','encryption_and_auth') | Set-Content -Path $target_file -ErrorAction Stop
        Write-Logging -Loglevel Information -Message "Changed secure file"
        }
    catch {
        Write-Logging -Loglevel Error -Message "Could not change secure file"
        }
    #Step 7.4 Copy certs to \Program Files\BMC Software\BladeLogic\RSCD\certs
    New-Item -ItemType "directory" -Path $cert_dir
    if (Test-Path $cert_dir) {
        Write-Logging -Loglevel Information -Message "Cert dir created"
        $certs | ForEach-Object {
            Copy-Item -Path $_ -Destination $cert_dir
            }
        }
    else {
        Write-Logging -Loglevel Error -Message "Could not create cert dir"
        }    
    }

#Step 8: start RSCD service
try {
    Get-Service -Name "RSCDsvc" | Start-Service -ErrorAction Stop
    Write-Logging -Loglevel Information -Message "RSCD service started"
}
catch {
    Write-Logging -Loglevel Error -Message "Could not start RSCD service"
}

#Step 9: Check RSCD port 4750
#wait 10 seconds for RSCD to start up
sleep 10
$rscd_port = Get-NetTcpConnection -LocalPort 4750 -LocalAddress 0.0.0.0 -State listen
if ($rscd_port) {
    $process_on_4750 = (Get-Process -Id ($rscd_port.OwningProcess)).ProcessName
    Write-Logging -Loglevel Information -Message $process_on_4750" is listening on port 4750."
    } else { 
    Write-Logging -Loglevel Error -Message "Nothing listening on port 4750. Please check RSCD service." 
    }

Write-Logging -Loglevel Information -Message "Installscript finished."


#packageinstaller -package-make="Ordner" // pinst commit xxx.job --ignore-signature
