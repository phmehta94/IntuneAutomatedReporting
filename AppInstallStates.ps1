<#

.COPYRIGHT
Copyright (c) Microsoft Corporation. All rights reserved. Licensed under the MIT license.
See LICENSE in the project root for license information.

#>

####################################################

# Variables
$subscriptionID = Get-AutomationVariable 'subscriptionID' # Azure Subscription ID Variable
$tenantID = Get-AutomationVariable 'tenantID' # Azure Tenant ID Variable
$resourceGroupName = Get-AutomationVariable 'resourceGroupName' # Resource group name
$storageAccountName = Get-AutomationVariable 'storageAccountName' # Storage account name

# Report specific Variables
$outputContainerName = Get-AutomationVariable 'appinstallstate' # Resource group name
$snapshotsContainerName = Get-AutomationVariable 'appinstallstatesnapshots' # Storage account name

# Graph App Registration Creds

# Uses a Secret Credential named 'GraphApi' in your Automation Account
$clientInfo = Get-AutomationPSCredential 'GraphApi'
# Username of Automation Credential is the Graph App Registration client ID 
$clientID = $clientInfo.UserName
# Password  of Automation Credential is the Graph App Registration secret key (create one if needed)
$secretPass = $clientInfo.GetNetworkCredential().Password

#Required credentials - Get the client_id and client_secret from the app when creating it in Azure AD
$client_id = $clientID #App ID
$client_secret = $secretPass #API Access Key Password

####################################################

function Get-AuthToken {

<#
.SYNOPSIS
This function is used to authenticate with the Graph API REST interface
.DESCRIPTION
The function authenticate with the Graph API Interface with the tenant name
.EXAMPLE
Get-AuthToken
Authenticates you with the Graph API interface
.NOTES
NAME: Get-AuthToken
#>

    param
    (
        [Parameter(Mandatory=$true)]
        $TenantID,
        [Parameter(Mandatory=$true)]
        $ClientID,
        [Parameter(Mandatory=$true)]
        $ClientSecret
    )
               
    try{
        # Define parameters for Microsoft Graph access token retrieval
        $resource = "https://graph.microsoft.com"
        $authority = "https://login.microsoftonline.com/$TenantID"
        $tokenEndpointUri = "$authority/oauth2/token"
               
        # Get the access token using grant type client_credentials for Application Permissions
        $content = "grant_type=client_credentials&client_id=$ClientID&client_secret=$ClientSecret&resource=$resource"
        $response = Invoke-RestMethod -Uri $tokenEndpointUri -Body $content -Method Post -UseBasicParsing -Verbose:$false

        Write-Host "Got new Access Token!" -ForegroundColor Green
        Write-Host

        # If the accesstoken is valid then create the authentication header
        if($response.access_token){
               
            # Creating header for Authorization token
               
            $authHeader = @{
                'Content-Type'='application/json'
                'Authorization'="Bearer " + $response.access_token
                'ExpiresOn'=$response.expires_on
            }
               
            return $authHeader
               
        }
        else{    
            Write-Error "Authorization Access Token is null, check that the client_id and client_secret is correct..."
            break    
        }
    }
    catch{    
        FatalWebError -Exeption $_.Exception -Function "Get-AuthToken"   
    }

}

####################################################

Function Get-ValidToken {

<#
    .SYNOPSIS
    This function is used to identify a possible existing Auth Token, and renew it using Get-AuthToken, if it's expired
    .DESCRIPTION
    Retreives any existing Auth Token in the session, and checks for expiration. If Expired, it will run the Get-AuthToken Fucntion to retreive a new valid Auth Token.
    .EXAMPLE
    Get-ValidToken
    Authenticates you with the Graph API interface by reusing a valid token if available - else a new one is requested using Get-AuthToken
    .NOTES
    NAME: Get-ValidToken
#>

    #Fixing client_secret illegal char (+), which do't go well with web requests
    $client_secret = $($client_secret).Replace("+","%2B")
               
    # Checking if authToken exists before running authentication
    if($global:authToken){
               
        # Get current time in (UTC) UNIX format (and ditch the milliseconds)
        $CurrentTimeUnix = $((get-date ([DateTime]::UtcNow) -UFormat +%s)).split((Get-Culture).NumberFormat.NumberDecimalSeparator)[0]
                              
        # If the authToken exists checking when it expires (converted to minutes for readability in output)
        $TokenExpires = [MATH]::floor(([int]$authToken.ExpiresOn - [int]$CurrentTimeUnix) / 60)
               
        if($TokenExpires -le 0){    
            Write-Host "Authentication Token expired" $TokenExpires "minutes ago! - Requesting new one..." -ForegroundColor Green
            $global:authToken = Get-AuthToken -TenantID $tenantID -ClientID $client_id -ClientSecret $client_secret    
        }
        else{
            Write-Host "Using valid Authentication Token that expires in" $TokenExpires "minutes..." -ForegroundColor Green
            #Write-Host
        }
    }    
    # Authentication doesn't exist, calling Get-AuthToken function    
    else {       
        # Getting the authorization token
        $global:authToken = Get-AuthToken -TenantID $tenantID -ClientID $client_id -ClientSecret $client_secret    
    }    
}

####################################################

Function Get-IntuneApplication(){

<#
.SYNOPSIS
This function is used to get applications from the Graph API REST interface
.DESCRIPTION
The function connects to the Graph API Interface and gets any applications added
.EXAMPLE
Get-IntuneApplication
Returns any applications configured in Intune
.NOTES
NAME: Get-IntuneApplication
#>

[cmdletbinding()]

param
(
    [parameter(Mandatory=$false)]
    [ValidateNotNullOrEmpty()]
    [string]$Name,
    [parameter(Mandatory=$false)]
    [ValidateNotNullOrEmpty()]
    [string]$type
)

$graphApiVersion = "Beta"
$Resource = "deviceAppManagement/mobileApps"

    try {

        if($Name){

        $uri = "https://graph.microsoft.com/$graphApiVersion/$($Resource)"
        (Invoke-RestMethod -Uri $uri -Headers $authToken -Method Get).Value | Where-Object { ($_.'displayName').contains("$Name") -and (!($_.'@odata.type').Contains("managed")) -and (!($_.'@odata.type').Contains("#microsoft.graph.iosVppApp")) }

        } elseif($type){

        $uri = "https://graph.microsoft.com/$graphApiVersion/$($Resource)"
        (Invoke-RestMethod -Uri $uri -Headers $authToken -Method Get).Value | Where-Object { ($_.'@odata.type').contains("$type") }

        }

        else {

        $uri = "https://graph.microsoft.com/$graphApiVersion/$($Resource)"
        (Invoke-RestMethod -Uri $uri -Headers $authToken -Method Get).Value | Where-Object { (!($_.'@odata.type').Contains("managed")) -and (!($_.'@odata.type').Contains("#microsoft.graph.iosVppApp")) }

        }

    }

    catch {

    $ex = $_.Exception
    Write-Host "Request to $Uri failed with HTTP Status $([int]$ex.Response.StatusCode) $($ex.Response.StatusDescription)" -f Red
    $errorResponse = $ex.Response.GetResponseStream()
    $reader = New-Object System.IO.StreamReader($errorResponse)
    $reader.BaseStream.Position = 0
    $reader.DiscardBufferedData()
    $responseBody = $reader.ReadToEnd();
    Write-Host "Response content:`n$responseBody" -f Red
    Write-Error "Request to $Uri failed with HTTP Status $($ex.Response.StatusCode) $($ex.Response.StatusDescription)"
    write-host
    break

    }

}

####################################################

Function Get-ApplicationAssignment(){

<#
.SYNOPSIS
This function is used to get an application assignment from the Graph API REST interface
.DESCRIPTION
The function connects to the Graph API Interface and gets an application assignment
.EXAMPLE
Get-ApplicationAssignment
Returns an Application Assignment configured in Intune
.NOTES
NAME: Get-ApplicationAssignment
#>

[cmdletbinding()]

param
(
    $ApplicationId
)

$graphApiVersion = "Beta"
$Resource = "deviceAppManagement/mobileApps/$ApplicationId/assignments"

    try {

        if(!$ApplicationId){

        write-host "No Application Id specified, specify a valid Application Id" -f Red
        break

        }

        else {

        $uri = "https://graph.microsoft.com/$graphApiVersion/$($Resource)"
        (Invoke-RestMethod -Uri $uri -Headers $authToken -Method Get).Value

        }

    }

    catch {

    $ex = $_.Exception
    $errorResponse = $ex.Response.GetResponseStream()
    $reader = New-Object System.IO.StreamReader($errorResponse)
    $reader.BaseStream.Position = 0
    $reader.DiscardBufferedData()
    $responseBody = $reader.ReadToEnd();
    Write-Host "Response content:`n$responseBody" -f Red
    Write-Error "Request to $Uri failed with HTTP Status $($ex.Response.StatusCode) $($ex.Response.StatusDescription)"
    write-host
    break

    }

}

####################################################

Function Get-AADGroup(){

<#
.SYNOPSIS
This function is used to get AAD Groups from the Graph API REST interface
.DESCRIPTION
The function connects to the Graph API Interface and gets any Groups registered with AAD
.EXAMPLE
Get-AADGroup
Returns all users registered with Azure AD
.NOTES
NAME: Get-AADGroup
#>

[cmdletbinding()]

param
(
    $GroupName,
    $id,
    [switch]$Members
)

# Defining Variables
$graphApiVersion = "v1.0"
$Group_resource = "groups"

    try {

        if($id){

        $uri = "https://graph.microsoft.com/$graphApiVersion/$($Group_resource)?`$filter=id eq '$id'"
        (Invoke-RestMethod -Uri $uri -Headers $authToken -Method Get).Value

        }

        elseif($GroupName -eq "" -or $GroupName -eq $null){

        $uri = "https://graph.microsoft.com/$graphApiVersion/$($Group_resource)"
        (Invoke-RestMethod -Uri $uri -Headers $authToken -Method Get).Value

        }

        else {

            if(!$Members){

            $uri = "https://graph.microsoft.com/$graphApiVersion/$($Group_resource)?`$filter=displayname eq '$GroupName'"
            (Invoke-RestMethod -Uri $uri -Headers $authToken -Method Get).Value

            }

            elseif($Members){

            $uri = "https://graph.microsoft.com/$graphApiVersion/$($Group_resource)?`$filter=displayname eq '$GroupName'"
            $Group = (Invoke-RestMethod -Uri $uri -Headers $authToken -Method Get).Value

                if($Group){

                $GID = $Group.id

                $Group.displayName
                write-host

                $uri = "https://graph.microsoft.com/$graphApiVersion/$($Group_resource)/$GID/Members"
                (Invoke-RestMethod -Uri $uri -Headers $authToken -Method Get).Value

                }

            }

        }

    }

    catch {

    $ex = $_.Exception
    $errorResponse = $ex.Response.GetResponseStream()
    $reader = New-Object System.IO.StreamReader($errorResponse)
    $reader.BaseStream.Position = 0
    $reader.DiscardBufferedData()
    $responseBody = $reader.ReadToEnd();
    Write-Host "Response content:`n$responseBody" -f Red
    Write-Error "Request to $Uri failed with HTTP Status $($ex.Response.StatusCode) $($ex.Response.StatusDescription)"
    write-host
    break

    }

}

####################################################

Function Get-InstallStatusForApp {

<#
.SYNOPSIS
This function will get the installation status of an application given the application's ID.
.DESCRIPTION
If you want to track your managed intune application installation stats as you roll them out in your environment, use this commandlet to get the insights.
.EXAMPLE
Get-InstallStatusForApp -AppId a1a2a-b1b2b3b4-c1c2c3c4
This will return the installation status of the application with the ID of a1a2a-b1b2b3b4-c1c2c3c4
.NOTES
NAME: Get-InstallStatusForApp
#>
	
[cmdletbinding()]

param
(
	[Parameter(Mandatory=$true)]
	[string]$AppId
)
	
	$graphApiVersion = "Beta"
	$Resource = "deviceAppManagement/mobileApps/$AppId/installSummary"
	
	try
	{

		$uri = "https://graph.microsoft.com/$graphApiVersion/$($Resource)"
		Invoke-RestMethod -Uri $uri -Headers $authToken -Method Get

	}
	
	catch
	{
		
		$ex = $_.Exception
		$errorResponse = $ex.Response.GetResponseStream()
		$reader = New-Object System.IO.StreamReader($errorResponse)
		$reader.BaseStream.Position = 0
		$reader.DiscardBufferedData()
		$responseBody = $reader.ReadToEnd();
		Write-Host "Response content:`n$responseBody" -f Red
		Write-Error "Request to $Uri failed with HTTP Status $($ex.Response.StatusCode) $($ex.Response.StatusDescription)"
		write-host
		break
		
	}
	
}

####################################################

Function Get-DeviceStatusForApp {

<#
.SYNOPSIS
This function will get the devices installation status of an application given the application's ID.
.DESCRIPTION
If you want to track your managed intune application installation stats as you roll them out in your environment, use this commandlet to get the insights.
.EXAMPLE
Get-DeviceStatusForApp -AppId a1a2a-b1b2b3b4-c1c2c3c4
This will return devices and their installation status of the application with the ID of a1a2a-b1b2b3b4-c1c2c3c4
.NOTES
NAME: Get-DeviceStatusForApp
#>
	
[cmdletbinding()]

param
(
	[Parameter(Mandatory=$true)]
	[string]$AppId
)
	
	$graphApiVersion = "Beta"
	$Resource = "deviceAppManagement/mobileApps/$AppId/deviceStatuses"
	
	try
	{

		$uri = "https://graph.microsoft.com/$graphApiVersion/$($Resource)"
		(Invoke-RestMethod -Uri $uri -Headers $authToken -Method Get).Value

	}
	
	catch
	{
		
		$ex = $_.Exception
		$errorResponse = $ex.Response.GetResponseStream()
		$reader = New-Object System.IO.StreamReader($errorResponse)
		$reader.BaseStream.Position = 0
		$reader.DiscardBufferedData()
		$responseBody = $reader.ReadToEnd();
		Write-Host "Response content:`n$responseBody" -f Red
		Write-Error "Request to $Uri failed with HTTP Status $($ex.Response.StatusCode) $($ex.Response.StatusDescription)"
		write-host
		break
		
	}
	
}


####################################################


#region Authentication

# Checking if authToken exists before running authentication
if($global:authToken){

    # Setting DateTime to Universal time to work in all timezones
    $DateTime = (Get-Date).ToUniversalTime()

    # If the authToken exists checking when it expires
    $TokenExpires = ($authToken.ExpiresOn.datetime - $DateTime).Minutes

    if($TokenExpires -le 0){

        Write-Output ("Authentication Token expired" + $TokenExpires + "minutes ago")

        #Calling Microsoft to see if they will give us access with the parameters defined in the config section of this script.
        Get-ValidToken

        $global:authToken = Get-AuthToken -TenantID $tenantID -ClientID $client_id -ClientSecret $client_secret
    }
}

# Authentication doesn't exist, calling Get-AuthToken function

else {

    #Calling Microsoft to see if they will give us access with the parameters defined in the config section of this script.
    Get-ValidToken

    # Getting the authorization token
    $global:authToken = Get-AuthToken -TenantID $tenantID -ClientID $client_id -ClientSecret $client_secret
}

#endregion

####################################################

$outputArray = @()

write-host "Getting all application install status per device" -f Green

$Applications = @()
$Applications += Get-IntuneApplication -type "windowsStoreApp"
$Applications += Get-IntuneApplication -type "StoreForBusinessApp"
$Applications += Get-IntuneApplication -type "windowsUniversalAppX"
$Applications += Get-IntuneApplication -type "win32LobApp"
$Applications += Get-IntuneApplication -type "webApp"
$Applications += Get-IntuneApplication -type "windowsMobileMSI"


foreach($app in $Applications) {
    
    $appName = $app.displayname
    $appID = $app.id

    write-host "App name: $appName" -f Yellow

    $deviceStatus = Get-DeviceStatusForApp -AppId $appID
    $assignments = Get-ApplicationAssignment -ApplicationId $appID

    foreach($assignment in $assignments) {

        $intent = $assignment.intent

        $groupName = (Get-AADGroup -id $assignment.target.groupID).displayName

        foreach($device in $deviceStatus) {
        
            $deviceName = $device.deviceName
            $installState = $device.installState
            $errorCode = $device.errorCode

            if($Assignment.target.'@odata.type' -eq "#microsoft.graph.allDevicesAssignmentTarget") {

                if($installState -inotlike "notApplicable") {

                    $outputArray += New-Object PSObject -Property @{

                        DeviceName = $deviceName
                        AppName = $appName
                        InstallState = $installState
                        ErrorCode = $errorCode
                        Intent = $assignment.intent
                        GroupName = "All Devices"
                    }
                }

            } elseif($Assignment.target.'@odata.type' -eq "#microsoft.graph.allLicensedUsersAssignmentTarget") {

                if($installState -inotlike "notApplicable") {

                    $outputArray += New-Object PSObject -Property @{

                        DeviceName = $deviceName
                        AppName = $appName
                        InstallState = $installState
                        ErrorCode = $errorCode
                        Intent = $assignment.intent
                        GroupName = "All Users"
                    }
                }
                
            } else {

                if($installState -inotlike "notApplicable") {

                    $outputArray += New-Object PSObject -Property @{

                        DeviceName = $deviceName
                        AppName = $appName
                        InstallState = $installState
                        ErrorCode = $errorCode
                        Intent = $assignment.intent
                        GroupName = $groupName
                    }

                }

            }
        
        }

    }
}

$outputArray | Export-Csv 'appInstallStates.csv' -NoTypeInformation -Force


$connectionName = "AzureRunAsConnection"
try
{
    # Get the connection "AzureRunAsConnection "
    $servicePrincipalConnection=Get-AutomationConnection -Name $connectionName         

    "Logging in to Azure..."
    Add-AzureRmAccount `
        -ServicePrincipal `
        -TenantId $servicePrincipalConnection.TenantId `
        -ApplicationId $servicePrincipalConnection.ApplicationId `
        -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint 
}
catch {
    if (!$servicePrincipalConnection)
    {
        $ErrorMessage = "Connection $connectionName not found."
        throw $ErrorMessage
    } else{
        Write-Error -Message $_.Exception
        throw $_.Exception
    }
}

Select-AzureRmSubscription -SubscriptionId $subscriptionID

Set-AzureRmCurrentStorageAccount -StorageAccountName $storageAccountName -ResourceGroupName $resourceGroupName

Set-AzureStorageBlobContent -Container $outputContainerName -File appInstallStates.csv -Blob appInstallStates.csv -Force

#Add snapshot file with timestamp
$date = Get-Date -format "dd-MMM-yyyy_HH:mm"
$timeStampFileName = "appInstallStates_" + $date + ".csv"
Set-AzureStorageBlobContent -Container $snapshotsContainerName -File appInstallStates.csv -Blob $timeStampFileName -Force

