# CriticalStart Close Function. Uploaded into Azure Runbooks and called within a logic app, triggered by Sentinel Automation Rule 
#against updated incidents with AutoSentinelClose, but not AutoCSClosed.
# Get Incidents with 1 of 2 tags, indicating that they have been auto-closed within sentinel through an automation rule or playbook and have not been processed with this function app.

#Recognizes Runbook environment, loads variables from Azure Automation Runbook Variables, logs into MgGraph & Azure as System-assigned Managed Identity
if ($PSPrivateMetadata.JobId.Guid){
    $Today = (Get-Date -format yyyy-MM-dd)
    Set-Alias -Name 'Output' -Value 'Write-Output' -Option AllScope
    $RunbookVariables = 'SentinelSubscription', 'SentinelResourceGroup', 'WorkspaceID', 'TenantId', 'CriticalStartAPI'
    foreach ($RunVar in $RunbookVariables) {
        $RunVal = Get-AutomationVariable -Name $RunVar
        New-Variable -Name $RunVar -Value $RunVal
    }
    Connect-AzAccount -Identity -Tenant $TenantId -Subscription $SentinelSubscription
    Set-AzContext -Subscription $SentinelSubscription
    Connect-MgGraph -Identity -NoWelcome
    $Job = Get-AzAutomationAccount | ForEach-Object {Get-AzAutomationJob -Id $PSPrivateMetadata.JobId -ResourceGroupName $_.ResourceGroupName -AutomationAccountName $_.AutomationAccountName -ErrorAction SilentlyContinue}
    $FilePath = $env:Temp + "\" + $Today + ' - ' + $Job.RunbookName + '.xlsx'
}

#Tag used within Sentinel Automation flows that have closed the ticket
$AutomatedSentinelTag = 'AutoSentinelClose'
#A tag used at the end of automation rules or logic apps to signify that the incident has been syncronized from Sentinel to MDR
$MDRSyncTag = 'AutoCSClosed'
#MDR Name
$MDRName = 'Critical Start'

$query = @"
SecurityIncident
| where TimeGenerated >= ago(7d)
| where Labels matches regex "($AutomatedSentinelTag)" and Status == 'Closed' and not (Labels matches regex "($MDRSyncTag)") and ClassificationComment !contains "$MDRName"
| summarize arg_max(TimeGenerated, *) by IncidentNumber
| summarize by Status, Title, Classification, CloseComment=ClassificationComment, IncidentNumber, ProviderIncidentId, tostring(AlertIds), tostring(Labels), AzSentinelId=IncidentName, Severity, ClassificationReason
"@
[array]$kqlQuery = Invoke-AzOperationalInsightsQuery -WorkspaceId $WorkspaceID -Query $query
$sentinelClosed = $kqlQuery.Results 

#Failsafe exit in case of faulty firing from Automation Rule
if ($sentinelClosed.count -eq 0){exit}

#Get All Open CS Incidents
$csIncidents = @()
$script:headers = @{
    'accept' = 'application/json'
    Authorization  = $CriticalStartAPI
}

$uri = 'https://portalapi.threatanalytics.io/api/1.5/incidents/?page=1&limit=1000&Incident%20Status=Open&Organization=Your%20Org%20Goes%20Here'
$csOpenIncidents = Invoke-RestMethod -Uri $uri -Method GET -Headers $headers
$uri = 'https://portalapi.threatanalytics.io/api/1.5/incidents/?page=1&limit=1000&Incident%20Status=Reviewing&Organization=Your%20Org%20Goes%20Here'
$csReviewingIncidents = Invoke-RestMethod -Uri $uri -Method GET -Headers $headers
$csIncidents += $csOpenIncidents
$csIncidents += $csReviewingIncidents

#Match KQL query result with open CS incidents based off title
$Mapped = @()
$csIncidents.objects | ForEach-Object {
    if ($_.Description -in $SentinelClosed.TItle) {
        $Mapped += $_
    }
}

#CS per Incident API request (SecurityIncident.IncidentNumber & SystemAlertId only available in this URI)
$csFilteredIncidents = @()
$Mapped | ForEach-Object {
    $uri = "https://portalapi.threatanalytics.io/api/1.5/incidents/$($_.id)/"
    $csResult = Invoke-RestMethod -Uri $uri -Method GET -Headers $headers
    $csFilteredIncidents += $csResult
}

#Map Sentinel Incident or SystemAlertId to CS Incident & get ClassificationComment from Sentinel incident
$verifiedClose = @()
$csFilteredIncidents | ForEach-Object {
    $csIncidentId = $_.id
    $similarAlerts = $_.similar_alerts 
    $incidentNumber = ($similarAlerts | ?{$_.key -match "SecurityIncident.IncidentNumber"}).values
    $SystemAlertId = ($similarAlerts | ?{$_.key -match "SystemAlertId"}).values
    $Lookup = $sentinelClosed | ?{$_.IncidentNumber -match $incidentNumber}# -or $_.AlertIds -match $SystemAlertId}
    if ($Lookup.count -gt 0) {
        $verifiedClose += @([pscustomobject]@{csIncident = $csIncidentId;CloseComment = $Lookup.CloseComment;Classification = $Lookup.Classification})
    }
}

#Close incidents in Critical Start
$Results=@()

$verifiedClose | ForEach-Object {
    #Map the Classification in SecurityIncident to the format in CS, use as verdict in json body
    switch ($_.Classification) {
        'BenignPositive' { $verdict = "benign_true_positive" }
        'TruePositive' { $verdict = "true_positive" }
        'FalsePositive' { $verdict = "false_positive" }
    }
    $body = @{
        user_confirmed = "false"
        description = $_.CloseComment
        outcome = "resolved"
        verdict = $verdict
    }
    $uri = "https://portalapi.threatanalytics.io/api/1.5/incidents/$($_.csIncident)/close/"
    $csResult = Invoke-RestMethod -Uri $uri -Method PUT -Headers $headers -Body ($body|ConvertTo-Json)
    $Results += $csResult
}

#Calculate Success & Output Results
$Misses = ($Results | ?{$_.status_display -match "(Open|Reviewing)"}).Count
if ($Misses -gt 0){Output "[$($Misses / $($Results.count))] Incidents Missed in $($MDRName) AutoClosure attempt."} else {Output "[$($Results.count)] Incidents successfully closed in $($MDRName) AutoClosure."}
$Results | Format-Table