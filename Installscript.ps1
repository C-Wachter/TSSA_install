#Requires -Version 5.0

<#
.SYNOPSIS

Installs TSSA RSCD Agent on target

.DESCRIPTION

This script will install TSSA RSCD Agent provided in $installation_file and configure it with the user data given as parameter.
It will also check if Visual C++ runtime is installed ($minimum_visual_c_runtime_version contains the required version)
and install the runtime module. if required.

.Parameter User

Connect string in the form 

Customer_L3AdminX:* rw,map=LocalAdmin
 
where 
Customer   - the name of the customer in TSSA
X          – it is the first letter of OS type on target server
                W – Windows
                L  –  Linux
                U  –  Unix
LocalAdmin - the name of the local administrator

.EXAMPLE

Installscript -user:'Kunde_L3AdminW:* rw,map=Administrator'

.INPUTS

None.

.OUTPUTS

None.

.NOTES

Minimum OS Architecture Supported: Windows Server 2016

Release Notes:
0.1 Initial version

By using this script, you accept the following terms.
Ownership Rights: Atos Information Technology GmbH (Atos) owns and will continue to own all right, title, and interest in and to the script, including the copyright.
Atos is giving the customer a limited license to use the script in accordance with these legal terms.
Use Limitation: This script may only be used for your legitimate business purposes, and may not be shared with another party.
Republication Prohibition: Under no circumstances may this script be re-published in any script library or website belonging to or under the control of any other company or software provider. 
Warranty Disclaimer: The script is provided “as is” and “as available”, without warranty of any kind. Atos makes no promise or guarantee that the script will be free from defects or that it will meet your specific needs or expectations. 
Assumption of Risk: Your use of the script is at your own risk. You acknowledge that there are certain inherent risks in using the script, and you understand and assume each of those risks. 
Waiver and Release: You will not hold Atos responsible for any adverse or unintended consequences resulting from your use of the script, and you waive any legal or equitable rights or remedies you may have against Atos relating to your use of the script. 

.LINK

Link to TSSA Sharepoint needed

.COMPONENT

Requires Atos Packageinstaller

#>


# ^2 lines distance !

#Parameter aus Kommandozeile übernehmen:
Param (
    [Parameter(Mandatory=$true)]
    [String]$User   #TSSA_Connect_String in the form 'Customer_L3AdminX:* rw,map=LocalAdmin'
)

#Konstanten werden hier definiert
[System.Version]$Minimum_Visual_C_Runtime_Version=14.32
$LogDateFormat = "%m/%d/%Y %H:%M:%S"

#Check environment variable %PINST_CACHE_PACKAGE_SOURCE%
if (!$env:PINST_CACHE_PACKAGE_SOURCE) {
    $path2executable = (Get-Location).Path
    }
else {
    $path2executable = $env:PINST_CACHE_PACKAGE_SOURCE
    }

#Funktionen werden hier definiert

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
# 3. Installation RSCD234-P1-WIN64.msi /qn usw.
# 4. RSCD service stoppen
# 5. Berechtigungen auf C:\Windows\rsc prüfen und ggfs setzen
# 6. Prüfen ob Param -Users mit SID500 übereinstimmt (optional)
# 7. Änderungen an users.local (param -users) und ggfs anderen Dateien
# 8. RSCD service starten

Write-Logging -Loglevel Information -Message "Installscript started"



#Step 1: Check VC++ Runtime
#Step 1.1: Find Installed Visual C++ Runtime 
$installed_SW = Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* | Select-Object DisplayName, DisplayVersion
$installed_Visual_C_Runtime = $installed_SW | Where-Object {$_.DisplayName -like 'Microsoft Visual C++*'} | Select-Object -Last 1

#Step 1.2: Check Installed Visual C++ Runtime version against required $Minimum_Visual_C_Runtime_Version
$install_VC = $false
switch ($installed_Visual_C_Runtime.Count) {
    0 { $install_VC = $true
        Write-Logging -Loglevel Information -Message "No Visual C++ found. Going to install..."
    }
    1 { if ($installed_Visual_C_Runtime.DisplayVersion -lt $Minimum_Visual_C_Runtime_Version) {
            $install_VC = $true
            Write-Logging -Loglevel Information -Message "No Visual C++ found. Going to install..."
            }
    }
}

#Step 2: Install Visual C++ Runtime if necessary
if ($install_VC -eq $true) {
    $executable="VC_redist.x64.exe"
    $arguments ="/install /quiet"
    $command2execute= Join-Path -Path $path2executable -ChildPath $executable
    Write-Logging -Loglevel Information -Message "Starting Visual C++ Runtime Installation" 
    $returncode Start-Process -Wait -FilePath $command2execute -WorkingDirectory $path2executable -ArgumentList $arguments
    if ($returncode -eq 0) {
        Write-Logging -Loglevel Information -Message "Visual C++ Runtime installed successfully"
    } else {
        Write-Logging -Loglevel Error -Message "Error installing Visual C++ Runtime"
    }
}

#Step 3: Installing RSCD agent
$executable="msiexec.exe"
$logfile=Join-Path -Path $env:temp -ChildPath TSSA_RSCD.log
$arguments="/i RSCD234-P1-WIN64.msi /quiet /qn /norestart /l "+$logfile
$returncode Start-Process -Wait -FilePath $command2execute -WorkingDirectory $path2executable -ArgumentList $arguments
if ($returncode -eq 0) {
    Write-Logging -Loglevel Information -Message "TSSA RSCD agent installed successfully"
} else {
    Write-Logging -Loglevel Error -Message "TSSA RSCD agent installing Visual C++ Runtime"
}





#combine path & exe...
#$command2execute= Join-Path -Path $path2executable -ChildPath $executable
#...and launch
#Start-Process -Wait -FilePath $command2execute -WorkingDirectory $path2executable -ArgumentList $arguments

#packageinstaller -package-make="Ordner" // pinst commit xxx.job --ignore-signature