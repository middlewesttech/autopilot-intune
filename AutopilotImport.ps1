# Get the ID and security principal of the current user account
$myWindowsID=[System.Security.Principal.WindowsIdentity]::GetCurrent()
$myWindowsPrincipal=new-object System.Security.Principal.WindowsPrincipal($myWindowsID)
 
# Get the security principal for the Administrator role
$adminRole=[System.Security.Principal.WindowsBuiltInRole]::Administrator
 
# Check to see if we are currently running "as Administrator"
if ($myWindowsPrincipal.IsInRole($adminRole))
   {
   # We are running "as Administrator" - so change the title and background color to indicate this
   $Host.UI.RawUI.WindowTitle = $myInvocation.MyCommand.Definition + "(Elevated)"
   $Host.UI.RawUI.BackgroundColor = "DarkBlue"
   clear-host
   }
else
   {
   # We are not running "as Administrator" - so relaunch as administrator
   
   # Create a new process object that starts PowerShell
   $newProcess = new-object System.Diagnostics.ProcessStartInfo "PowerShell";
   
   # Specify the current script path and name as a parameter
   $newProcess.Arguments = $myInvocation.MyCommand.Definition;
   
   # Indicate that the process should be elevated
   $newProcess.Verb = "runas";
   
   # Start the new process
   [System.Diagnostics.Process]::Start($newProcess);
   
   # Exit from the current, unelevated, process
   exit
   }
 
# Run your code that needs to be elevated here
Write-Host -NoNewLine "Press any key to continue..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

<#

.SYNOPSIS

    This script will download and install AzureAD and WindowsAutoPilotIntune modules and it will
    download and install Get-WindowsAutoPilotInfo script. It will then create autopilot csv file and it will import created csv file in the Autopilot.
    It will also allow you to set up a Group Tag, assign the user to the device, and add them to the MDM Enrollment User Scope.

.NOTES

  Colton Coan - 12/20/2019




#>

$progressPreference = 'silentlyContinue'
$serial = (Get-WmiObject -Class win32_bios).serialnumber

# Intune Login Account
Write-Host "Enter your Azure Administrator account here" -ForegroundColor Cyan
$user = Read-Host "Enter your Azure Administrator account here"

# Downloading and installing Azure AD and WindowsAutoPilotIntune Module
Write-Host "Downloading and installing AzureAD module" -ForegroundColor Cyan
Install-Module AzureAD,WindowsAutoPilotIntune,Microsoft.Graph.Intune -Force

# Importing required modules
Import-Module -Name AzureAD,WindowsAutoPilotIntune,Microsoft.Graph.Intune 

# Downloading and installing get-windowsautopilotinfo script
Write-Host "Downloading and installing get-windowsautopilotinfo script" -ForegroundColor Cyan
Install-Script -Name Get-WindowsAutoPilotInfo -Force

# Intune Login
Write-Host "Connecting to Microsoft Graph" -ForegroundColor Cyan

Try {
    Connect-MSGraph -Credential (Get-credential -username $user -message "Type in the password")
    write-host "Successfully connected to Microsoft Graph" -foregroundcolor green
}
Catch {
    write-host "Error: Could not connect to Microsoft Graph. Please login with the account that has premissions to administer Intune and autopilot or verify your password" -foregroundcolor red 
Break }


# Creating temporary folder to store autopilot csv file 

Write-Host "Checking if Temp folder exist in C:\" -ForegroundColor Cyan

IF (!(Test-Path C:\Temp) -eq $true) {

    Write-Host "Test folder was not found in C:\. Creating Test Folder..." -ForegroundColor Cyan
    New-Item -Path C:\Temp -ItemType Directory | Out-Null
}

Else { Write-Host "Test folder already exist" -ForegroundColor Green }

# Creating Autopilot csv file
Write-Host "Creating Autopilot CSV File" -ForegroundColor Cyan
Try {
    Get-WindowsAutoPilotInfo.ps1 -OutputFile "C:\Temp\$serial.csv"
    Write-Host "Successfully created autopilot csv file" -ForegroundColor Green}

Catch {
    write-host "Error: Something went wrong. Unable to create csv file." -foregroundcolor red 
Break }
 
 #Group Tag Menu

 function Show-Menu
{
    param (
        [string]$Title = 'Group Tag Selection'
    )
    Clear-Host
    Write-Host "================ $Title ================"
    
    Write-Host "Sales: Type Sales to be assigned the Sales group tag"
    Write-Host "HR: Type HR to be assigned the Sales group tag"
    Write-Host "Legal:   Type Legal to be assigned the Sales group tag"
    Write-Host "IT: Type IT for this group"
}

     Show-Menu
     $selection = Read-Host "Please make a selection"
     switch ($selection)
     {
         'Sales' {
             'Assigning to Sales'
         } 'HR' {
             'Assigning to HR'
         } 'Legal' {
             'Assigning to Legal'
        } 'IT' {
             'Assigning to IT'}
     }
     pause

#Importing CSV File into Intune
Write-Host "Importing Autopilot CSV File into Intune" -ForegroundColor Cyan
Try {
    Import-AutoPilotCSV -csvFile "C:\Temp\$serial.csv" -groupTag $selection
    Write-Host "Successfully imported autopilot csv file" -ForegroundColor Green}

Catch {
    Write-Host "Error: Something went wrong. Please check your csv file and try again"
    Break}

    Invoke-AutopilotSync 

# Connecting to AzureAD
Connect-AzureAD -Credential (Get-credential -username $user -message "Type in the password")

# End User Information
Write-Host "Type in the end user being given this device" -ForegroundColor Cyan
$enduser=Read-host "Type in the end user being given this device"

# Getting information

    get-azureadgroup -SearchString "az-autopilot-enrollment-prod" | Select ObjectID -OutVariable groupobjectid
    get-azureaduser -objectid "$enduser" | Select ObjectID -OutVariable userobjectid
    get-azureaduser -objectid "$enduser" | Select DisplayName -OutVariable displayname
    Add-AzureADGroupMember -ObjectId "b19d16c1-5585-43a1-a931-52a256d3d6ab" -RefObjectId "e38fa301-e070-4735-92e5-07a869ece9db"
    Write-Host "Successfully added the user to MDM Enrollment group." -ForegroundColor Green

Try {
#Connecting back to Intune
connect-msgraph
#Adding User to Device
Get-AutoPilotDevice -serial "$serial" | Set-AutoPilotDevice -userPrincipalName "$enduser" -addressableUserName "$displayname" -displayName "$displayname"
Invoke-AutopilotSync 
Write-host "Success! The user has been assigned to the device and it has been synced. Please verify completion in the portal and then provision the device!" -ForegroundColor Green
$wshell = New-Object -ComObject Wscript.Shell
$wshell.Popup("Operation Completed! You may exit now.",0,"Autopilot for Existing Devices Successful",0x1)}

Catch {
    Write-Host "Failed to Add User to Device"
    Break}
