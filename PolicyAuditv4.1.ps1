## Adam Morgan.  Copyright Concept Technology, Inc. 2018.
## Outputs PolicyAudit.csv containing policy and other info for all endpoints at all sites.
## Intended to help locate machines incorrectly set to the wrong policy.

## March 2018 - replaced hard-coded credentials with pop-up prompts.
## April 2018 - added windows version to output. Added logic to check if cred variables 
##   already defined (so you can paste-in the commands to define them from KeePass before 
##   running script to save time).
##  v3a - 10/26/2018 added PolicyId to output since PolicyName is now blank and appears
##      to have been deprecated?
##  v3b - incorporated new WebRequest syntax and error-handling. Incporporated syntax 
##      to pull results in page sizes of 50 at a time (since we're getting timeouts 
##      on 300, and some sites now have more than that!)
##  v4.0 - Move new code block for getting Sites info into a function.
##  v4.1 - Increased PageSize, consolidated .csv writes into one export line at the end.
##         Added capability to export to .xlsx.

##NOTE ON USAGE: Excel output requires installing PowerShell module: https://github.com/dfinke/ImportExcel.
##If that module's not present, a .csv is exported instead.

## Includes syntax from a script by Robbie Vance at 
## http://pleasework.robbievance.net/howto-get-webroot-endpoints-using-unity-rest-api-and-powershell/

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

# The base URL for which all REST operations will be performed against
$BaseURL = 'https://unityapi.webrootcloudav.com'
# You must first get a token which will be good for 300 seconds of future queries.  We do that from here
$TokenURL = "$BaseURL/auth/token"
# All Rest Credentials must be first converted to a base64 string so they can be transmitted in this format
$Credentials = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($APIClientID+":"+$APIPassword ))


##################### Functions
Function Get-Token {
	Param (
		$myCredentials,
		$myTokenURL,
		$myWebrootUser,
		$myWebrootPassword
	)
	write-host "Requesting REST token..." -ForegroundColor Green;
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
	$Return.AccessToken = (Invoke-RestMethod @TokenParams).access_token;
	#start token timer
	$Return.TokenStartTime = get-date -format HH:mm:ss;
	#Output these 2 var
	Return $Return;
}

Function Check-TokenTimer {
	Param (
	[DateTime]$myTokenStartTime
	)
	$TimeNow = get-date -format HH:mm:ss
	$TimeDiff = New-TimeSpan $myTokenStartTime $TimeNow

    #OPTIONAL: Statically definte start and end dates:
    $myStartDate = "2018-08-01"
    $myEndDate = "2018-08-31T24:59:59"

	#return the time difference
	Return $TimeDiff
}

Function Get-Sites {
	Param ($Token)
	Write-Host "Get sites data" -ForegroundColor Green
	$SitesUri = "$BaseURL/service/api/console/gsm/$GsmKey/sites";
	$header = @{
			"Authorization" = "Bearer "+ $Token.AccessToken;
			"Content-Type" = 'application/json';
			"Accept" = 'application/json';
	}
	#Make Request, retry until success or $i.
	$i = 0;
	$Quit=0;
	Do {
		$i++; #increment counter
		$Request = Invoke-WebRequest -Uri $SitesUri -Header $header -ContentType 'application/json' -Method Get -TimeoutSec 30;	
		#$Request.StatusCode;
		If (($i -eq 10) -or ($Request.StatusCode -eq 200)) {$Quit = 1;}
	} Until ($Quit=1)
	#Exit with message if request failed.
	If ($Request.StatusCode -ne 200) {
		Write-Host "REST request for sites list failed, exiting script.";
		Exit;
	}
	#Convert to object $Sites.
	$JsonRequest = $Request | ConvertFrom-Json; 
	$Sites = $JsonRequest.Sites | Where-Object {$_.Deactivated -eq $false};
	Return $Sites; #Return object containing Sites info.
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

##################### End of Functions


#Get token
Write-Host "Get token" -ForegroundColor Green
$Token = Get-Token $Credentials $TokenURL $WebrootUser $WebrootPassword
#Get list of sites
$Sites = Get-Sites $Token;


#Get endpoints info for each site.

# For every non-deactivated site, get endpoint info and append to csv.
$Sites | Where-Object {$_.Deactivated -eq $false} |
	ForEach-Object { 
		#First check Token Timer by calling function and handing it the start time from the last token request.
		$TimeDiff = Check-TokenTimer $Token.TokenStartTime
		#If Token is over 4 minutes old, get new one and reset timer
		if ($TimeDiff.Minutes -eq 4) {
			write-host "Token over 4 minutes old, requesting fresh one..." -ForegroundColor Green
			$Token = Get-Token $Credentials $TokenURL $WebrootUser $WebrootPassword
		}
		
		$mySiteName = $_.SiteName; #Get name of site for which we're about to list endpoints
		write-host "";
		write-host "Getting endpoint info for site $mySiteName";
		$mySiteID = $_.SiteId;

		
		# List all endpoints for this site, showing only desired properties.  Add SiteName as extra property to each item in object. Filter-out deactivated entries.
		$i = 1; #Initialize page counter
		Do { #Get 50 at a time
			$TryCount = 1;
			$EndpointIDURL = "$BaseURL/service/api/console/gsm/$GsmKey/sites/$mySiteId/endpoints?type=activate&pagesize=100&pageNr=$i";
			Do { #Retry page request until success
				$Failure=0;
				$header = @{
				"Authorization" = "Bearer "+ $Token.AccessToken;
				"Content-Type" = 'application/json';
				"Accept" = 'application/json';
				}
				Try {
					Write-Host "Requesting Page $i, (attempt $TryCount)";
					$Request = Invoke-WebRequest -Uri $EndpointIDURL -Header $header -ContentType 'application/json' -Method Get -TimeoutSec 20;	
				} catch {
					Write-Host "Request attempt $TryCount failed, retrying...";
					$Failure=1;
					#In case token expired or last token request failed, request new one
					$Token = Get-Token $Credentials $TokenURL $WebrootUser $WebrootPassword;
				}
				$TryCount++; #increment counter
			} Until ($Failure -eq 0)

			#Convert to object $Endpoints.
			$JsonRequest = $Request | ConvertFrom-Json;
			$TotalAvailable = $JsonRequest.TotalAvailable; #(see api https://unityapi.webrootcloudav.com/Docs/en/APIDoc/Api/GET-api-console-gsm-gsmKey-sites-siteId-endpoints_type_hostName_machineId_order_orderDirection_pageSize_pageNr)
			Write-Host "TotalAvailable is $TotalAvailable";
			$Endpoints = $JsonRequest.Endpoints;
			
			#get count
			$EndpointCount = $Endpoints.count;

			#Add the site name to the output of this loop iteration, and prepare it to be added to the growing total output object.
			$MyOutput = $Endpoints | ForEach-Object {$_|add-member -type noteproperty -name SiteName -value $mySiteName;$_} | 
				Where-Object {$_.Deactivated -eq $false} | 
				Select-Object -Property SiteName,HostName,PolicyName,PolicyId,WindowsFullOS,Mac,MACAddress,LastSeen,EndpointId | 
				Sort-Object SiteName,PolicyId,Hostname;
			
			#Append these results to a single growing object that will be written to file at the end.
			$TotalOutput = $TotalOutput + $MyOutput;
				
			#Write-Host "i is $i";
			$i++; #Increment page counter
		#} until ($EndpointCount -eq 0)
		} until ($TotalAvailable -le ($i * 50))
	}

#Sort final object.
$TotalOutput = $TotalOutput | Sort-Object SiteName;
	
#Export to Excel if Export-Excel module installed, otherwise just use native export-csv cmdlet.
If (Test-CommandExists Export-Excel) {$TotalOutput | Export-Excel "PolicyAudit.xlsx" -Append -FreezeTopRow -AutoSize}
	else {$TotalOutput | Export-Csv -Append -Path "PolicyAudit.csv" -NoTypeInformation}
	
write-host ""
write-host "--------------------------------"
write-host "Script Finished"
exit
