#
# Adapted from darrenrobinson blogs / trial and error with our Sailpoint Tenant. YMMY
# We use Adaxes https://www.adaxes.com/ as a frontend and the logging functions are built to utilize their logging system. Log functions could be replaced with writeHost of other means
# Passing 'Email' value through Adaxes TargetObject via IADS interface on the AD Object in Question.



# Moudle Import
Import-Module SailPointIdentityNow
Import-Module CredentialManager

#Slack webhook for posting errors / terminations
$uriSlack = "https://hooks.slack.com/services/yourwebhookhere"
function Logger([string]$log_message) {
    $Context.LogMessage("$log_message", "Information")
}

# Creating SailPoint IdentityNow configuration on all api versions
$orgName = "yourorgnamehere"
Set-IdentityNowOrg -orgName $orgName
$adminCreds = Get-StoredCredential -Target IdentityNowAdmin
$v3Creds = Get-StoredCredential -Target IdentityNowV3
$v2Creds = Get-StoredCredential -Target IdentityNowV2

Set-IdentityNowCredential -AdminCredential $adminCreds -v2APIKey $v2Creds -v3APIKey $v3Creds 
Save-IdentityNowConfiguration

# Pulling email from AD Object could be a static var or input coming from elsewhere
$email = $Context.TargetObject.EmailAddress

Logger("Starting Terminator-v3")
$exactEmail = ""

try{   
    # Get exact email
    $searchv3 = "{
        `n  `"indices`": [
        `n    `"identities`"
        `n  ],
        `n  `"query`": {
        `n    `"query`": `"attributes.email.exact:`\`"$($email)`\`"`",
        `n    `"fields`": [
        `n      `"name`",
        `n      `"description`"
        `n    ]
        `n  }
        `n}"
    
    $getExactEmailResponse = (Invoke-IdentityNowRequest -Method Post -Uri "https://$($orgName).api.identitynow.com/v3/search/identities?limit=10" -body $searchv3 -Headers HeadersV3_JSON)
    $getExactEmailResponseJSON = $getExactEmailResponse | ConvertTo-Json

    
    If ($getExactEmailResponseJSON.Count -gt 1) {
       Write-Host "More than one identity found with that email: $($email) ...exiting"
       Logger("More than one identity found with that email: $($email) ...exiting")
       $body1 = ConvertTo-Json @{
        pretext = "Terminator-v3 Hooks"
        text = "More than one identity found with that email: $($email) ...exiting"
        color = "#142954"
       }
       Invoke-RestMethod -uri $uriSlack -Method Post -body $body1 -ContentType 'application/json' | Out-Null
       Exit
    }
    ElseIf ($getExactEmailResponseJSON.Count -lt 1){
       Write-Host "No identity found with that email: $($email) ...exiting"
       Logger("No identity found with that email: $($email) ...exiting")
       $body2 = ConvertTo-Json @{
        pretext = "Terminator-v3 Hooks"
        text = "No identity found with that email: $($email) ...exiting"
        color = "#142954"
       }
       Invoke-RestMethod -uri $uriSlack -Method Post -body $body2 -ContentType 'application/json' | Out-Null
       Exit
    }
    $exactEmail = $getExactEmailResponse.email
    Write-Host "$($exactEmail)"
} catch {
    Write-Host "Request failed!"
    Logger("Request failed!")
    $body3 = ConvertTo-Json @{
        pretext = "Terminator-v3 Hooks"
        text = "Request Failed!"
        color = "#142954"
       }
       Invoke-RestMethod -uri $uriSlack -Method Post -body $body3 -ContentType 'application/json' | Out-Null
    Exit
}


# Sorters for API v1 call
$sorters = @{"property"="name"; "direction"="ASC"} | convertto-json
$sortersEncoded = [System.Web.HttpUtility]::UrlEncode(($sorters))

# Filters for API v1 call
$filters = @{"property"="email"; "value"="$($exactEmail)"} | convertto-json
$filtersEncoded = [System.Web.HttpUtility]::UrlEncode(($filters))

$getIDResponse = (Invoke-IdentityNowRequest -Method Get -Uri "https://$($orgName).identitynow.com/api/user/list?start=0&limit=1&sorters=$($sortersEncoded)&filters=$($filtersEncoded)" -headers HeadersV3)
$id = $getIDResponse.items.id
Write-Host "($id)"

# JSON body for 'updateLifecycleState' POST-request
$fields = @{"id"="$($id)";"lifecycleState"="inactive"} | convertto-json

try{
    $updateLcsResponse = (Invoke-IdentityNowRequest -Method Post -Uri "https://$($orgName).identitynow.com/api/user/updateLifecycleState" -body $fields -headers HeadersV3_JSON)
    Write-Host "CloudLifeCycle State Successfully changed to Inactive"
    Logger("CloudLifeCycle State Successfully changed to Inactive")
      $body4 = ConvertTo-Json @{
        pretext = "Terminator-v3 Hooks"
        text = "CloudLifeCycle State Successfully changed to Inactive for $($email)"
        color = "#142954"
       }
       Invoke-RestMethod -uri $uriSlack -Method Post -body $body4 -ContentType 'application/json' | Out-Null  
} catch {
    Write-Host "Request failed: .../api/user/updateLifecycleState"
    Logger("Request failed: .../api/user/updateLifecycleState")
        Logger("CloudLifeCycle State Successfully changed to Inactive")
      $body5 = ConvertTo-Json @{
        pretext = "Terminator-v3 Hooks"
        text = "Request failed: .../api/user/updateLifecycleState"
        color = "#142954"
       }
       Invoke-RestMethod -uri $uriSlack -Method Post -body $body5 -ContentType 'application/json' | Out-Null  
}
