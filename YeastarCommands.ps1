###################################################
## SENSITIVE KEY INFORMATION HERE       ###########
###################################################
## THE FOLLOWING THREE LINES ARE SENSITIVE AND SHOULD NEVER BE SHARED
$ApiPublicKey = '' # Change this to match the API username of the YMP PBX System
$ApiPrivateKey = '' # Change this to match the API Password of the YMP PBX System
$YmpHostname = '' # Change this to match the hostname of the YMP PBX System


## DO NOT CHANGE ANYTHING BELOW THIS LINE ##
############################################
# These following two lines are needed for the YMP to maintain an open connection, but are not used for anything beyond that
$callappport = '' #enter the port number of a public web server that will respond 200 to any request
$callapplication = '' #enter the url of a public web server that will respond 200 to any request

$YmpHostname = $YmpHostname.replace('https://','').replace('/','') # used to cleanup the hostname variations

$ympBaseUrl = 'https://$YmpHostname/api/v1.1.0' #tack on the API Endpoint base URL

# Used for encrypting the API Password into MD5 for API Auth
function New-EncryptedMD5String {
param(
$StringToEncrypt
)
$stringAsStream = [System.IO.memorystream]::new()
$writer = [System.IO.StreamWriter]::new($stringAsStream)
$Writer.Write($StringToEncrypt)
$Writer.Flush()
$stringAsStream.Position = 0
return (Get-FileHash -InputStream $stringAsStream -Algorithm MD5).hash.toLower()
}

# Setup the connection
function Start-YMPConnection {

$Username = $Global:ApiPublicKey
$Password = New-EncryptedMD5String -StringToEncrypt $Global:ApiPrivateKey

$Body = @{
username = $Username
password = $Password
port = $callappport
url = $callapplication
urltag = 1
}

$PostData = $Body|ConvertTo-Json

if ($null -eq $Global:AuthResult -or $Global:AuthResult.status -ne 'Success') {
    Write-Host "Missing authentication, refreshing token" -ForegroundColor Green
    $Global:AuthResult = irm -Method POST -Uri "https://$YmpHostname/api/v1.10/login" -ContentType Application/JSON -Body $PostData
    $Global:AuthTime = Get-Date
}

# Refresh token every 25 minutes to be safe
if ((Get-Date $AuthTime).AddMinutes(25) -le (Get-Date)) {
    $Global:AuthResult = irm -Method POST -Uri "$ympBaseUrl/token/refresh" -Body (@{refreshtoken=$AuthResult.refreshtoken}|ConvertTo-Json) -ContentType Application/JSON
    $Global:AuthTime = Get-Date
}
    $token = $Global:AuthResult.token
    return $token
}

# Logout
function End-YMPConnection {
# Retrieve the current token to perform logout
$token = Start-YMPConnection

$LogoutStep = irm -Method POST -Uri "$ympBaseUrl/logout?token=$token"
$Global:AuthResult = $null
Remove-Variable -Name AuthResult,AuthTime -Scope Global
return $LogoutStep
}

# Get a list of ALL Sip Trunks
function Get-YMPSipTrunks {
$token = Start-YMPConnection
$QueryResult = irm -Method POST -Uri "$ympBaseUrl/trunklist/query?token=$token" -ContentType Application/JSON
return $QueryResult

}

# Get a single SIP Trunks full config, you will need to specify the name of the sip trunk
function Get-YMPSipTrunk {
param(
$sipTrunkName
)

$requestBody = (@{trunkname=$sipTrunkName}|convertto-json)

$token = Start-YMPConnection
$QueryResult = irm -Method POST -Uri "$ympBaseUrl/siptrunk/query?token=$token" -Body $requestBody -ContentType Application/JSON
return $QueryResult
}

# Get a list of YMP Extensions and their status
function Get-YMPExtensionList {
$token = Start-YMPConnection
$QueryResult = irm -Method POST -Uri "$ympBaseUrl/extensionlist/query?token=$token" -ContentType Application/JSON
return $QueryResult
}

# Get the full configuration of an extension. Leave extid blank to retrieve ALL extensions and their settings
function Get-YMPExtensionDetails {
param(
$extid
)

$token = Start-YMPConnection

$RequestDetails = @{
uri = "$ympBaseUrl/extension/query?token=$token"
method = 'POST'
contenttype = 'Application/JSON'
body = if ($extid) {(@{extid=$extid}|convertto-json)} else {$null}
}

$QueryResults = irm @RequestDetails

return $QueryResults
}

# Specify either -inbound or -outbount to pull a list of active phone calls
function Get-YmpActiveCalls {
param(
[switch]$Inbound,
[switch]$Outbound,
$inboundid,
$outboundid
)

$token = Start-YMPConnection

if ($Inbound -and !$Outbound) {

$RequestDetails = @{
uri = "$ympBaseUrl/inbound/query?token=$token"
method = 'POST'
contenttype = 'application/json'
}

$QueryResults = irm @RequestDetails

}

if ($Outbound -and !$Inbound) {

$RequestDetails = @{
uri = "$ympBaseUrl/outbound/query?token=$token"
method = 'POST'
contenttype = 'application/json'
}

$QueryResults = irm @RequestDetails

}

return $QueryResults

}

# Seems to be broken, or unsure how to specify the file name, in any case it should call the number you specify and play the prompt when the call is answered. Include an internal extension to use that extension settings to make the external call.
function Play-YmpPromptOnExternal {
param(
[string]$ExternalNumber,
[array]$PromptName,
[string]$UsingExtNo
)

$token = Start-YMPConnection
$PromptName = ($PromptName -join '+').ToString()

$body = (@{
outto = $ExternalNumber
prompt = $PromptName
fromext = if ($UsingExtNo) {$UsingExtNo} else {$null}
}|convertto-json)

Write-Host "Attempting to play $PromptName on phone number $ExternalNumber" -ForegroundColor Green

$RequestDetails = @{
method = 'POST'
uri = "$ympBaseUrl/outbound/playprompt?token=$token"
contenttype = 'application/json'
body = $body
}

$QueryResults = irm @RequestDetails
return $QueryResults
}
