## Adam Morgan, Concept Technology, Inc.  
## Last modified April 8, 2018.
## Finds duplicate agents for all by MAC Address in GSM.

## IMPORTANT NOTES:
## At the end it will give errors for each empty or deactivated site - this is ok.
## If the working directory already contains a file name "duplicates.csv", this
## script will append entries to the end instead of replacing it, so delete your existing file
## before running it.

## Version 1 of this script simply exported info for all endpoints (including non-duplicates) to "endpoints.csv".
## Version 2 only gets info for duplicate entries, and puts them into "duplicates.csv".
## Version 4 added logic to re-request REST token as needed since it expires after 5 minutes.
##           Also moved some code into functions, and added prompts for credential information.
## Version 5 discovered that script was only pulling the first 50 endpoints for each site.  
##           By default the request uses a pageSize of 50, and I wasn't checking for subsequent pages.
##           In this version I've simply done a quick workaround by using a pageSize of 300, since I 
##           have no sites with more than that.
##           Also added logic to include "SiteID" in exported csv, to enable another script to 
##           deactivate them.
## Version 6 Added logic to check if cred variables already defined (so you can paste-in the commands to define them
##			 from KeePass before running script to save time).
## Version 7 Make it export InstanceMID as well (as a better way than MAC of identifying duplicates)

## Contains REST syntax from a script by Robbie Vance at  http://pleasework.robbievance.net/howto-get-webroot-endpoints-using-unity-rest-api-and-powershell/



#####################################
### This block prompts you for 5 variables that are all specific to your GSM instance and accounts, etc.  
### Alternatively, you can comment-out this block and instead hard-code the variables in the next block, 
### which is more convenient for testing but not recommended for permanent use, since you shouldn't 
### leave passwords in plain-text files.
### The "try" logic checks to see if you've already defined the credentials variables (for example,
### by pasting in a command block from KeePass before running the script), and if so, skips the cred prompts.
try {
    Get-Variable WebrootUser -Scope Global -ErrorAction 'Stop'
} catch [System.Management.Automation.ItemNotFoundException] {
    #Variables not already defined, so prompt for them.
	Add-Type -AssemblyName Microsoft.VisualBasic
	$WebrootUser = [Microsoft.VisualBasic.Interaction]::InputBox('Enter your Webroot GSM username, the one you use to login to the web portal:', 'Webroot GSM Username', "")
	$WebrootPassword = [Microsoft.VisualBasic.Interaction]::InputBox('Enter your Webroot GSM password, the one you use to login to the web portal:', 'Webroot GSM Password', "")
	$GsmKey = [Microsoft.VisualBasic.Interaction]::InputBox('Enter your Webroot global GSM keycode:', 'Webroot GSM Key', "")
	$APIClientID = [Microsoft.VisualBasic.Interaction]::InputBox('Enter your Webroot API Access Client ID:', 'API Access Client ID', "")
	$APIPassword = [Microsoft.VisualBasic.Interaction]::InputBox('Enter your Webroot API Access Client Password:', 'API Access Client Password', "")
}

<#
#####################################
### These variables are all specific to your GSM instance and accounts, etc.  
### I left this block here if you want to hard-code your passwords temporarily for testing purposes.
# An administrator user for your Webroot portal -- this is typically the same user you use to login to the main portal
$WebrootUser = 'jdoe@mycompany.com'
## This is typically the same password used to log into the main portal
$WebrootPassword = 'xxxxxxxxxxxxxxxx'
# global GSM keycode (same for all admins and sites)
$GsmKey = 'A1A1-B2B2-C3C3-D4D4-E5E5'
# This must have previously been generated from the Webroot GSM for the site you wish to view
$APIClientID = 'client_FIWn3BFu@mycompany.com'
$APIPassword = 'xxxxxxxxxxxxx'
#>


######################################
### These are common variables that you don't need to change
# The base URL for which all REST operations will be performed against
$BaseURL = 'https://unityapi.webrootcloudav.com'
# You must first get a token which will be good for 300 seconds of future queries.  We do that from here
$TokenURL = "$BaseURL/auth/token"
# Once we have the token, we must get the SiteID of the site with the keycode we wish to view Endpoints from
$SiteIDURL = "$BaseURL/service/api/console/gsm/$GsmKey/sites"
# All Rest Credentials must be first converted to a base64 string so they can be transmitted in this format
$Credentials = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($APIClientID+":"+$APIPassword ))


########### Functions
Function Get-Token {
	Param (
		$myCredentials,
		$myTokenURL,
		$myWebrootUser,
		$myWebrootPassword
	)
	write-host "Requesting REST token..." -ForegroundColor Green
	$TokenParams = @{
				"ErrorAction" = "Stop"
				"URI" = $myTokenURL
				"Headers" = @{"Authorization" = "Basic "+ $myCredentials}
				"Body" = @{
							  "username" = $myWebrootUser
							  "password" = $myWebrootPassword
							  "grant_type" = 'password'
							  "scope" = 'Console.GSM'
							}
				"Method" = 'post'
				"ContentType" = 'application/x-www-form-urlencoded'
				}
	#create hash table to hold variables we want to return
	[hashtable]$Return = @{} 
	$Return.AccessToken = (Invoke-RestMethod @TokenParams).access_token
	#start token timer
	$Return.TokenStartTime = get-date -format HH:mm:ss
	#Output these 2 var
	Return $Return
}

Function Check-TokenTimer {
	Param (
	[DateTime]$myTokenStartTime
	)
	$TimeNow = get-date -format HH:mm:ss
	$TimeDiff = New-TimeSpan $myTokenStartTime $TimeNow
	
	#return the time difference
	Return $TimeDiff
}

########### End of functions



#Call function to request token and place it in $Token.AccessToken.
#Also stores current token start time in $Token.TokenStartTime (as part of the function that's called)
$Token = Get-Token $Credentials $TokenURL $WebrootUser $WebrootPassword


write-host "Getting endpoint data for each site..." -ForegroundColor Green
$Params = @{
            "ErrorAction" = "Stop"
            "URI" = $SiteIDURL
            "ContentType" = "application/json"
            "Headers" = @{"Authorization" = "Bearer "+ $Token.AccessToken}
            "Method" = "Get"
        }

# Loop through every site, get endpoint info for each.
(Invoke-RestMethod @Params).Sites | 
	ForEach-Object {
		$mySiteName = $_.SiteName #Get name of site for which we're about to list endpoints
		write-host $mySiteName
		$mySiteID = $_.SiteId
		$EndpointIDURL = "$BaseURL/service/api/console/gsm/$GsmKey/sites/$mySiteId/endpoints?type=activated%pageSize=300"
		#Check Token Timer by calling function and handing it the start time from the last token request.
		$TimeDiff = Check-TokenTimer $Token.TokenStartTime
		#If Token is over 4 minutes old, get new one and reset timer
		if ($TimeDiff.Minutes -eq 4) {
			write-host "Token over 4 minutes old, requesting fresh one..." -ForegroundColor Green
			$Token = Get-Token $Credentials $TokenURL $WebrootUser $WebrootPassword
		}
		
		## New array for the GET request we'll be sending for each site
		$Params2 = @{
            "ErrorAction" = "Stop"
            "URI" = $EndpointIDURL
            "ContentType" = "application/json"
            "Headers" = @{"Authorization" = "Bearer "+ $Token.AccessToken}
            "Method" = "Get"
        }
		# Get all endpoints for this site. Add properties for SiteName and Duplicate (yes/no).
		$mySite = (Invoke-RestMethod @Params2).Endpoints | 
			foreach-object {$_|add-member -type noteproperty -name SiteName -value $mySiteName;$_} | 
			foreach-object {$_|add-member -type noteproperty -name Duplicate -value $false;$_} | 
			foreach-object {$_|add-member -type noteproperty -name SiteID -value $mySiteID;$_} | 
			Where-Object {$_.Deactivated -eq $false} | 
			Select-Object SiteName,HostName,MACAddress,LastSeen,Duplicate,SiteId,EndpointId,MachineId | 
			Sort-Object MACAddress,LastSeen
	
		#Mark duplicates
		$MACcount = $mySite | group-object -Property MACAddress | Where-Object -Filter {$_.Count -ge "2"}
		$mySite | Foreach-Object {if ($MACcount.Name -contains $_.MACAddress) {$_.Duplicate = $true}}
		#add duplicates to growing csv file
		$mySite | Where-Object -Filter {$_.Duplicate -eq $true} | Export-Csv -Append -Path "Duplicates.csv"	
	}
write-host ""
write-host "--------------------------------"
write-host "Script Finished" -ForegroundColor Green
exit
