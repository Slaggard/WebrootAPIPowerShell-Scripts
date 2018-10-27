## Adam Morgan, last modified 3/28/2018
## Deactivates a list of GSM endpoints in a file named DeleteThese.csv.

## Useful for removing duplicates found with my WebrootAuditDuplicatesv4.ps1 script.

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
##########------------------------------####
## These variables are specific to your console and credentials these variables.
# global GSM keycode (same for all admins and sites)
$GsmKey = ''

# An administrator user for your Webroot portal -- this is typically the same user you use to login to the main portal
$WebrootUser = ''
 
# This is typically the same password used to log into the main portal
$WebrootPassword = ''
 
# This must have previously been generated from the Webroot GSM for the site you wish to view
$APIClientID = ''
$APIPassword = ''
##########------------------------------####
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
#####################################

## Begin by using creds to request REST token, to be used for all future requests
write-host
write-host "Get token" -ForegroundColor Green
$Params = @{
            "ErrorAction" = "Stop"
            "URI" = $TokenURL
            "Headers" = @{"Authorization" = "Basic "+ $Credentials}
            "Body" = @{
                          "username" = $WebrootUser
                          "password" = $WebrootPassword
                          "grant_type" = 'password'
                          "scope" = 'Console.GSM'
                        }
            "Method" = 'post'
            "ContentType" = 'application/x-www-form-urlencoded'
            }
 
$AccessToken = (Invoke-RestMethod @Params).access_token


#Read-in DeleteThese.csv to an object.
$myfile = Import-Csv DeleteThese.csv
$myfile | Sort-Object SiteName,Hostname	|
	foreach-object {
		$mysite = $_.SiteID		
		$DeactivateURL = "$BaseURL/service/api/console/gsm/$GsmKey/sites/$mysite/endpoints/deactivate"
		write-host "Sending Request: " -NoNewline
		write-output $DeactivateURL
		
		$Params3 = @{
			"ErrorAction" = "Stop"
			"URI" = $DeactivateURL
			"Headers" = @{"Authorization" = "Bearer "+ $AccessToken}
			"Body" = @{"EndpointsList" = $_.EndpointID}
			"Method" = 'post'
			"ContentType" = 'application/x-www-form-urlencoded'
		}
	#Send the deactivation request
	Invoke-RestMethod @Params3
	}
write-host "Script finished successfully"
exit
