## AMorgan Oct 2018.
## Outputs ThreatAudit.csv (or xlsx) containing list of detected threats at all sites.
## NOTES ON USAGE:
## Excel output requires installing PowerShell module: https://github.com/dfinke/ImportExcel.
## The "?startdate" URL paramater filters based on the "LastSeen" values.  Default is 24 hrs ago.
##    Syntax is like this: startDate=2018-09-01  OR startDate=2018-07-05T20:24:59.2558569Z.
## The "&returnedInfo=ExtendedInfo" parameter returns MD5, dwell time, and other values.  Don't know how to ##    pull those values out ofyet
## Includes syntax from a script by Robbie Vance at 
## http://pleasework.robbievance.net/howto-get-webroot-endpoints-using-unity-rest-api-and-powershell/
##
##
## v1 Pulls data for all sites, last 3 days, sometimes times-out on a specific site.  This version's 
##    kind of a test.
## v2 Added token timer function to re-request token if script's ran so long that it expired.  Added logic to pull pages of 50 results
##    and loop through pages.
## v3 Split the rest call and the parsing of that returned object apart.  Replaced multiple file writes with a single large object that grows each iteration and then is written to file at end of script.
## v4 Tried to add logic to REST request to handle timeout exceptions gracefully, it's kind of a mess.
## v5 Better error handling and loop logic for looping through pages.
 
 #IN PROGRESS
 
 
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

#Define function Test-CommandExists.  We'll use this to see if cmdlet Export-Excel is installed.
Function Test-CommandExists {
	Param ($command)
	$oldPreference = $ErrorActionPreference
	$ErrorActionPreference = 'stop'
	try {if(Get-Command $command){RETURN $true}}
	Catch {Write-Host "$command does not exist"; RETURN $false}
	Finally {$ErrorActionPreference=$oldPreference}
} 

#Define StartDate parameter for API call.  Defines how far back you want
#    records from.  Currently it simply gets last 3 days (for running daily checks). 
#    Otherwise you can not call it and define them statically.
Function Define-Startdate {
	$myDate = (Get-Date).AddDays(-3);
	$year = $myDate.Year
	$month = $myDate.Month
	$day = $myDate.Day
	$myStartDate = "$year-$month-$day"
	Return $myStartDate
}

Function Check-TokenTimer {
	Param (
	[DateTime]$myTokenStartTime
	)
	$TimeNow = get-date -format HH:mm:ss
	$TimeDiff = New-TimeSpan $myTokenStartTime $TimeNow

    #OPTIONAL: Statically definte start and end dates:
    $myStartDate = "2018-10-01"
    $myEndDate = "2018-10-31T24:59:59"

	#return the time difference
	Return $TimeDiff
}
########### End of functions


###########Begin script

#Call function to request token and place it in $Token.AccessToken.
#Also stores current token start time in $Token.TokenStartTime (as part of the function that's called)
$Token = Get-Token $Credentials $TokenURL $WebrootUser $WebrootPassword

write-host "Get sites data" -ForegroundColor Green
$Params = @{
            "ErrorAction" = "Stop"
            "URI" = $SiteIDURL
            "ContentType" = "application/json"
            "Headers" = @{"Authorization" = "Bearer "+ $Token.AccessToken}
            "Method" = "Get"
        }

$myStartDate = Define-Startdate{}; #Define startdate for your API call.


# For every site, get threat info and append to csv.
(Invoke-RestMethod @Params).Sites | 
	ForEach-Object {
		#First check Token Timer by calling function and handing it the start time from the last token request.
		$TimeDiff = Check-TokenTimer $Token.TokenStartTime
		#If Token is over 4 minutes old, get new one and reset timer
		if ($TimeDiff.Minutes -eq 4) {
			write-host "Token over 4 minutes old, requesting fresh one..." -ForegroundColor Green
			$Token = Get-Token $Credentials $TokenURL $WebrootUser $WebrootPassword
		}

		$mySiteName = $_.SiteName #Get name of site for which we're about to list threats
		write-host ""
		write-host "Getting threat info for site $mySiteName"
		$mySiteID = $_.SiteId
		#$EndpointIDURL = "$BaseURL/service/api/console/gsm/$GsmKey/sites/$mySiteId/threathistory?startDate=$myStartDate&PageSize=200"
		#manually specify range
		
		$i = 1; #initialize counter for do loop, represents page number.
		# For each site, get pages of 50 results each, until a page with less than 50 is returned.
		do {
			write-host "DO loop i: $i for $mySiteName";
			$EndpointIDURL = "$BaseURL/service/api/console/gsm/$GsmKey/sites/$mySiteId/threathistory?startDate=$myStartDate&endDate=#myEndDate&PageSize=50&pageNr=$i"

			## New array for the GET request we'll be sending for each site
			$Params2 = @{
				"ErrorAction" = "Stop"
				"URI" = $EndpointIDURL
				"ContentType" = "application/json"
				"Headers" = @{"Authorization" = "Bearer "+ $Token.AccessToken}
				"Method" = "Get"
			}
			#v4 make hash table to store call-related values, see https://zeleskitech.com/2016/09/23/making-better-rest-calls-powershell/
			#[hashtable]$Private:return = @{}
			#$Private:return.status = 0
			#First simply make the request and store as MyOutput.  Catch failure, and if it's a 504, try again.
			#do {
				try {
					$MyOutput = (Invoke-RestMethod @Params2).ThreatRecords;
				} catch {
					$msg = "API request failed!";
                    Write-debug $msg;
					$Private:return.exception = $_.Exception
					$Private:return.status = 1
					$statuscode = [int]$Private:return.exception.response.statuscode   #Get statuscode as int.
					write-host "API request failed with statuscode $statuscode." -ForegroundColor Red;
				}
			#} while ($statuscode -eq 504)

			#get count
			$mycount=$MyOutput.count;	
			
			#Now perform parsing on MyOutput.
			# List all threats detected for this site since $myStartDate, showing only desired properties.  Add SiteName as extra property to each item in object. 
			$MyOutput =  $MyOutput| 
				foreach-object {$_|add-member -type noteproperty -name SiteName -value $mySiteName;$_}|
				Select-Object -Property SiteName,HostName,FileName,PathName,MalwareGroup,FirstSeen,LastSeen;
			
			#Append these results to a single growing object that will be written to file at the end.
			$TotalOutput = $TotalOutput + $MyOutput;

			write-host "count is $mycount";
			$i++;
		} until ($mycount -eq 0)
		
		$totalcount = $TotalOutput.count;
		write-host "Totalcount is $totalcount";
	}

#Sort final object.
$TotalOutput = $TotalOutput | Sort-Object SiteName,Hostname,FileName,LastSeen;
	
#Export to Excel if Export-Excel module installed, otherwise just use native export-csv cmdlet.
If (Test-CommandExists Export-Excel) {$TotalOutput | Export-Excel "ThreatAudit.xlsx" -Append -FreezeTopRow -AutoSize}
	else {$TotalOutput | Export-Csv -Append -Path "ThreatAudit.csv" -NoTypeInformation}
	
	
write-host ""
write-host "--------------------------------"
write-host "Script Finished"
exit
