$global:AppId = Get-AutomationVariable -Name 'AppId'
$global:tenantId = Get-AutomationVariable -Name 'TenantId'
$global:appSecret = Get-AutomationVariable -Name 'AppSecret'

#[Core] Environment variables
$Today = (Get-Date -format yyyy-MM-dd)
$AzAutomationJob = Get-AzAutomationAccount | ForEach-Object { Get-AzAutomationJob -Id $PSPrivateMetadata.JobId -ResourceGroupName $_.ResourceGroupName -AutomationAccountName $_.AutomationAccountName }
$RunbookName = $AzAutomationJob.RunbookName
$SentinelSubscription = Get-AutomationVariable -Name 'SentinelSubscription'
$WorkspaceID = Get-AutomationVariable -Name 'WorkspaceId'
$TenantId = Get-AutomationVariable -Name 'TenantId'
$AdminNamingConvention = Get-AutomationVariable -Name 'AdminNamingConvention'
#[Core] Number of days to look back within SignInLogs for KQL query, default of 30 days.
$QueryLookback = Get-AutomationVariable -Name 'QueryLookback'
#[Core] Distinct number of logins per user over X days for KQL query, default of 50 distinct logins.
$QueryDistinctLogins = Get-AutomationVariable -Name 'QueryDistinctLogins'

function TagRetired {
    param (
        [string]$Action,
        [string]$Value,
        [array]$Machines
    )
    $body = @{
        "Value" = $Value;
        "Action" = $Action;
        "MachineIds" = $Machines
    }
    $URL = "https://api.securitycenter.microsoft.com/api/machines/AddOrRemoveTagForMultipleMachines"
    if ($Machines.count -gt 500){
        $Done = $false
        $Start = 0
        $End = 499
        do {
            $500Machines = $Machines[$Start..$End]
            $body = @{
                "Value" = $Value;
                "Action" = $Action;
                "MachineIds" = $500Machines
            }
            if ($Action -eq 'Remove') {Output "Removing device tag:$($Value) from machines: $($Start)-$($End) / $($Machines.count)"} else {Output "$($Action)ing device tag:$($Value) to machines: $($Start)-$($End) / $($Machines.count)"}
            try { 
                $global:webResponse = Invoke-WebRequest -Method Post -Uri $URL -Headers $headers -Body ($body | ConvertTo-Json) -ContentType "application/json" -ErrorAction Stop 
            }
            Catch {
                $Message = $_.ErrorDetails.Message
                $StatusCode = $_.ErrorDetails.StatusCode
                Output "ErrorMessage: $($_.ErrorDetails.Message) $($_.Exception.Response.StatusCode)"
                $RemoveId = @()
                switch -regex ($Message) {
                    '"MachineIds do not exist: (?<Id>.+)",' {$RemoveId += $matches.Id.Split(",")}
                }
                if ($RemoveId) {
                    $500Machines = $500Machines | ?{$_ -notIn $RemoveId}
                    $Body.MachineIds = $500Machines
                    try { $global:webResponse = Invoke-WebRequest -Method Post -Uri $URL -Headers $headers -Body ($body | ConvertTo-Json) -ContentType "application/json" -ErrorAction Stop }
                    Catch {
                        if ($_.ErrorDetails.Message) {
                            $Message = $_.ErrorDetails.Message
                            $StatusCode = $_.ErrorDetails.StatusCode
                            Output "ErrorMessage: $($_.ErrorDetails.Message) $($_.Exception.Response.StatusCode)"
                        }
                    }
                }
            }
            if ($webResponse.StatusCode -eq '200') {Output 'Status: Success'} else {Output "Status: $($webResponse.StatusCode)"}
            if ($End -eq $Machines.count){$Done = $true}
            $Start = $Start+500
            $End = $End+500
            if ($End -gt $Machines.count){$End = $Machines.count}
        }
        while ($Done -ne $true)
    }
    else {
        if ($Action -eq 'Remove') {Output "Removing device tag:$($Value) to $($Machines.count) assets"} else {Output "$($Action)ing device tag:$($Value) to $($Machines.count) assets"}
        try { $global:webResponse = Invoke-WebRequest -Method Post -Uri $URL -Headers $headers -Body ($body | ConvertTo-Json) -ContentType "application/json" -ErrorAction Stop }
        Catch {
            if ($_.ErrorDetails.Message) {
                $Message = $_.ErrorDetails.Message
                $StatusCode = $_.ErrorDetails.StatusCode
                Output "ErrorMessage: $($_.ErrorDetails.Message) $($_.Exception.Response.StatusCode)"
                $RemoveId=@()
                switch -regex ($Message) {
                    '"MachineIds do not exist: (?<Id>.+)",' {$RemoveId += $matches.Id.Split(",")}
                }
                if ($RemoveId) {
                    $Machines = $Machines | ?{$_ -notIn $RemoveId}
                    $Body.MachineIds = $Machines
                    try { $global:webResponse = Invoke-WebRequest -Method Post -Uri $URL -Headers $headers -Body ($body | ConvertTo-Json) -ContentType "application/json" -ErrorAction Stop }
                    Catch {
                        if ($_.ErrorDetails.Message) {
                            $Message = $_.ErrorDetails.Message
                            $StatusCode = $_.ErrorDetails.StatusCode
                            Output "ErrorMessage: $($_.ErrorDetails.Message) $($_.Exception.Response.StatusCode)"
                        }
                    }
                }
            }
            else {
                if ($webResponse.StatusCode -eq '200') {Output 'Status: Success'} else {Output "Status: $($webResponse.StatusCode)"}
            }
        }
    }
}
function GetToken {
    Output 'Connecting...'

    $resourceAppIdUri = 'https://securitycenter.onmicrosoft.com/windowsatpservice'
    $oAuthUri = "https://login.microsoftonline.com/$TenantId/oauth2/token"
    $authBody = [Ordered] @{
        resource      = "$resourceAppIdUri"
        client_id     = "$appId"
        client_secret = "$appSecret"
        grant_type    = 'client_credentials'
    }
    $authResponse = Invoke-RestMethod -Method Post -Uri $oAuthUri -Body $authBody -ErrorAction Stop
    $token = $authResponse.access_token
    $script:headers = @{
        'Content-Type' = 'application/json'
        Accept         = 'application/json'
        Authorization  = "Bearer $token"
    }
    if ($authresponse) {
        Output "Connected"
        return $headers
    }
    else {
        Output "Connection Failed"
        Output "ErrorMessage: " + $Error[0] , "Error"
    }
    $authBody=""
}

#[Core] Determine if running within Automation Runbook or server/workstation & change command parameters as needed.
if ($PSPrivateMetadata.JobId) {
    Set-Alias -Name Output -Value Write-Output
    $FilePath = $env:Temp + "\" + $Today + ' - ' + $RunbookName + '.xlsx'
    GetToken
    Connect-AzAccount -Identity -Tenant $TenantId -Subscription $SentinelSubscription
    Set-AzContext -Subscription $SentinelSubscription
    Connect-MgGraph -Identity -NoWelcome
    $DomainList= Get-MgDomain | Where-Object{$_.AuthenticationType -eq 'Managed'} | Select-Object -Property Id
    $Domains = $DomainList.Id -join '|'
}
else {
    Set-Alias -Name Output -Value Write-Host
    $FilePath = "c:\temp\" + $Today + ' - DefenderXDRTagging.xlsx'
    GetToken
    Connect-AzAccount -Tenant $TenantId -Subscription $SentinelSubscription
    Set-AzContext -Subscription $SentinelSubscription
    Connect-MgGraph -NoWelcome
    #[Core] Filter KQL sign-in logs to known domains list (e.g. '(domain.com|domain2.com)')
    $DomainList= Get-MgDomain | Where-Object{$_.AuthenticationType -eq 'Managed'} | Select-Object -Property Id
    $Domains = $DomainList.Id -join '|'
}

Start-ThreadJob -Name 'DeviceMapping' -ScriptBlock {
$query = @"
SigninLogs
| where TimeGenerated >= ago($using:QueryLookback`d)
| extend Device = parse_json(DeviceDetail)
| extend isManaged = Device.isManaged
| extend isCompliant = Device.isCompliant
| extend operatingSystem = Device.operatingSystem
| extend DeviceName = Device.displayName
| extend deviceId = Device.deviceId
| extend User = tolower(UserPrincipalName)
| where IsInteractive == true and isManaged == true and isCompliant == true and operatingSystem startswith 'Windows'
| where not(User matches regex '$using:AdminNamingConvention') and User matches regex @'($using:Domains)'
| project isManaged, isCompliant, operatingSystem, DeviceName, AppDisplayName, UserId, tostring(deviceId), User
| summarize Logins=count() by tostring(DeviceName), UserId, deviceId, User
| where Logins >= $using:QueryDistinctLogins
| project Logins, DeviceName, User, UserId, deviceId
| order by Logins desc, User asc
"@
[array]$kqlQuery = Invoke-AzOperationalInsightsQuery -WorkspaceId $using:WorkspaceID -Query $query
$kqlQuery.Results
} | Out-Null

#Get Intune setting for deviceDecom period, defaulting to 90 if not set
$IntuneRetireDays = (Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/beta/deviceManagement/ManagedDeviceCleanupSettings").deviceInactivityBeforeRetirementInDays
if ($IntuneRetireDays) {$IntuneRetireDays = (Get-Date (Get-Date).AddDays(-$IntuneRetireDays) -format yyyy-MM-dd)} else {$IntuneRetireDays = (Get-Date (Get-Date).AddDays(-90) -format yyyy-MM-dd)}
$InactiveDays = Get-Date (Get-Date).AddDays(-7) -format yyyy-MM-dd
$InactiveTag='Inactive'
$RetireTag = 'Retired'
$SharedTag = 'Shared'

#Build list of devices to work off of
$RetiredQuery = (Invoke-WebRequest -Method Get -Uri "https://api.securitycenter.microsoft.com/api/machines/findbytag?tag=Retired&useStartsWithFilter=true" -Headers $headers | ConvertFrom-Json).value
$InactiveQuery = (Invoke-WebRequest -Method Get -Uri "https://api.securitycenter.microsoft.com/api/machines/findbytag?tag=Inactive&useStartsWithFilter=true" -Headers $headers | ConvertFrom-Json).value
$SharedQuery = (Invoke-WebRequest -Method Get -Uri "https://api.securitycenter.microsoft.com/api/machines/findbytag?tag=Shared&useStartsWithFilter=true" -Headers $headers | ConvertFrom-Json).value
$RemoveRetireTag = $RetiredQuery | ?{[string]$_.machineTags -match $RetireTag -and $_.lastSeen -gt $IntuneRetireDays -and $_.isExcluded -eq $false}
$RemoveInactiveTag = $InactiveQuery | ?{[string]$_.machineTags -match $InactiveTag-and $_.lastSeen -gt $InactiveDays}
$Inventory = (Invoke-WebRequest -Method Get -Uri "https://api.security.microsoft.com/api/machines" -Headers $headers | ConvertFrom-Json).value
$DeviceMapping = Receive-Job -Name 'DeviceMapping' -Wait -AutoRemoveJob

#[Core] Determine commonly shared devices from SignInLogs
Start-ThreadJob -Name 'SharedDevices' -ScriptBlock {
    $Devices = @()
    foreach ($Object in $using:DeviceMapping){
        $Temp=$Devices
        $Lookup = $using:DeviceMapping | ?{$_.deviceId -match $Object.deviceId -and $Object.deviceId -notIn $Temp.deviceId}
        if ($Lookup.count -gt 1){
            $Lookup = $Lookup | Sort-Object -Property User -Unique | Select-Object *
            $Devices += $Lookup
            $Lookup
        }
    }
} | Out-Null

$AddRetireTag = $Inventory | ?{$_.lastSeen -lt $IntuneRetireDays -and [string]$_.machineTags -notmatch $RetireTag -and $_.isExcluded -eq $false} | Sort-Object -Property lastSeen -Descending
$AddInactiveTag = $Inventory | ?{$_.lastSeen -lt $InactiveDays -and [string]$_.machineTags -notmatch $InactiveTag} | Sort-Object -Property lastSeen -Descending

#Tag assets in blocks of 500 at a time
if ($AddRetireTag.count -gt 0) {TagRetired -Action 'Add' -Value $RetireTag -Machines $AddRetireTag.id} else {Output "No $RetireTag devices to tag."}
if ($RemoveRetireTag.count -gt 0) {TagRetired -Action 'Remove' -Value $RetireTag -Machines $RemoveRetireTag.id} else {Output "No devices to remove $RetireTag tag from"}
if ($AddInactiveTag.count -gt 0) {TagRetired -Action 'Add' -Value $InactiveTag -Machines $AddInactiveTag.id} else {Output "No $InactiveTag devices to tag."}
if ($RemoveInactiveTag.count -gt 0) {TagRetired -Action 'Remove' -Value $InactiveTag -Machines $RemoveInactiveTag.id} else {Output "No devices to remove $InactiveTag tag from"}

Output "Calculating shared workstations..."
$Shared = Receive-Job -Name 'SharedDevices' -Wait -AutoRemoveJob
$SharedDevices = $Shared | Sort-Object -Property deviceId -Unique
Output "SharedDevices: $($SharedDevices.count)"
$SharedRef = $Inventory | ?{$_.aadDeviceId -in $SharedDevices.deviceId}
$SharedExisting = $SharedQuery | ?{$_.id -in $SharedRef.id}
$AddSharedTag = $SharedRef | ?{$_.id -notIn $SharedExisting.id}
Output "SharedRef: $($SharedRef.count)"
Output "AddSharedTag: $($AddSharedTag.count)"
$RemoveSharedTag = $SharedQuery | ?{$_.id -notIn $SharedRef.id}
Output "RemoveSharedTag: $($RemoveSharedTag.count)"

if ($AddSharedTag.count -gt 0) {TagRetired -Action 'Add' -Value $SharedTag -Machines $AddSharedTag.id} else {Output "No $SharedTag devices to tag."}
if ($RemoveSharedTag.count -gt 0) {TagRetired -Action 'Remove' -Value $SharedTag -Machines $RemoveSharedTag.id} else {Output "No devices to remove $SharedTag tag from"}

$RetiredQuery = (Invoke-WebRequest -Method Get -Uri "https://api.securitycenter.microsoft.com/api/machines/findbytag?tag=Retired&useStartsWithFilter=true" -Headers $headers | ConvertFrom-Json).value
$InactiveQuery = (Invoke-WebRequest -Method Get -Uri "https://api.securitycenter.microsoft.com/api/machines/findbytag?tag=Inactive&useStartsWithFilter=true" -Headers $headers | ConvertFrom-Json).value
$SharedQuery = (Invoke-WebRequest -Method Get -Uri "https://api.securitycenter.microsoft.com/api/machines/findbytag?tag=Shared&useStartsWithFilter=true" -Headers $headers | ConvertFrom-Json).value

Output "Retired: $($RetiredQuery.count)"
Output "Inactive: $($InactiveQuery.count)"
Output "Shared: $($SharedQuery.count)"