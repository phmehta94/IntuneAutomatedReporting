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
$outputContainerName = Get-AutomationVariable 'deviceconfigurationgroup' # Resource group name
$snapshotsContainerName = Get-AutomationVariable 'deviceconfigurationgroupsnapshots' # Storage account name

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

Function Get-DeviceConfigurationPolicy(){

<#
.SYNOPSIS
This function is used to get device configuration policies from the Graph API REST interface
.DESCRIPTION
The function connects to the Graph API Interface and gets any device configuration policies
.EXAMPLE
Get-DeviceConfigurationPolicy
Returns any device configuration policies configured in Intune
.NOTES
NAME: Get-DeviceConfigurationPolicy
#>

[cmdletbinding()]

param
(
    $name
)

$graphApiVersion = "Beta"
$DCP_resource = "deviceManagement/deviceConfigurations"

    try {

        if($Name){

        $uri = "https://graph.microsoft.com/$graphApiVersion/$($DCP_resource)"
        (Invoke-RestMethod -Uri $uri -Headers $authToken -Method Get).Value | Where-Object { ($_.'displayName').contains("$Name") }

        }

        else {

        $uri = "https://graph.microsoft.com/$graphApiVersion/$($DCP_resource)"
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

Function Get-DeviceConfigurationPolicyAssignment(){

<#
.SYNOPSIS
This function is used to get device configuration policy assignment from the Graph API REST interface
.DESCRIPTION
The function connects to the Graph API Interface and gets a device configuration policy assignment
.EXAMPLE
Get-DeviceConfigurationPolicyAssignment $id guid
Returns any device configuration policy assignment configured in Intune
.NOTES
NAME: Get-DeviceConfigurationPolicyAssignment
#>

[cmdletbinding()]

param
(
    [Parameter(Mandatory=$true,HelpMessage="Enter id (guid) for the Device Configuration Policy you want to check assignment")]
    $id
)

$graphApiVersion = "Beta"
$DCP_resource = "deviceManagement/deviceConfigurations"

    try {

    $uri = "https://graph.microsoft.com/$graphApiVersion/$($DCP_resource)/$id/groupAssignments"
    (Invoke-RestMethod -Uri $uri -Headers $authToken -Method Get).Value

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
# pseudo-group identifiers for all users and all devices
[string]$AllUsers   = "acacacac-9df4-4c7d-9d50-4ef0226f57a9"
[string]$AllDevices = "adadadad-808e-44e2-905a-0b7873a8a531"

    try {

        if($id){

        $uri = "https://graph.microsoft.com/$graphApiVersion/$($Group_resource)?`$filter=id eq '$id'"
        switch ( $id ) {
                $AllUsers   { $grp = [PSCustomObject]@{ displayName = "All users"}; $grp           }
                $AllDevices { $grp = [PSCustomObject]@{ displayName = "All devices"}; $grp         }
                default     { (Invoke-RestMethod -Uri $uri -Headers $authToken -Method Get).Value  }
                }
                
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

$DCPs = Get-DeviceConfigurationPolicy

write-host

$outputArray = @()

foreach($DCP in $DCPs){

    write-host "Device Configuration Policy:"$DCP.displayName -f Yellow
    write-host

    $id = $DCP.id

    $DCPA = Get-DeviceConfigurationPolicyAssignment -id $id
    write-host "Getting Configuration Policy assignment..." -f Cyan
    
    $DCPA

    if($DCPA){
        
        if($DCPA.count -gt 1){

            foreach($group in $DCPA){

                $groupname = (Get-AADGroup -id $group.targetGroupId).displayName

                $outputArray += New-Object PSObject -Property @{

                    PolicyName = $DCP.displayName
                    LastModifiedDate = $DCP.lastModifiedDateTime
                    CreatedDateTime = $DCP.createdDateTime
                    GroupName = $groupname
                    IsExcludeGroup = $group.excludeGroup
                    
                }
            }

        }

        else {

            $groupname = (Get-AADGroup -id $DCPA.targetGroupId).displayName

            $outputArray += New-Object PSObject -Property @{

                PolicyName = $DCP.displayName
                LastModifiedDate = $DCP.lastModifiedDateTime
                CreatedDateTime = $DCP.createdDateTime
                GroupName = $groupname
                IsExcludeGroup = $group.excludeGroup
            }

        }

    }

    else {

        Write-Host "No assignments found."

    }

    Write-Host

}

$outputArray | Export-Csv 'DeviceConfigurationGroups.csv' -NoTypeInformation -Force


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

Set-AzureStorageBlobContent -Container $outputContainerName -File DeviceConfigurationGroups.csv -Blob DeviceConfigurationGroups.csv -Force

#Add snapshot file with timestamp
$date = Get-Date -format "dd-MMM-yyyy_HH:mm"
$timeStampFileName = "DeviceConfiguration_" + $date + ".csv"
Set-AzureStorageBlobContent -Container $snapshotsContainerName -File DeviceConfigurationGroups.csv -Blob $timeStampFileName -Force