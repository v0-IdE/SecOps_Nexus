#Requirements:
#Modules: Az.Accounts, Az.OperationalInsightsQuery, ImportExcel, Microsoft.Graph
#Access to Sentinel Workspace with McasShadowItReporting Table setup.
#Graph: Domain.Read.All

#Get all domains dynamically using graph
$DomainList= Get-MgDomain | Where-Object{$_.AuthenticationType -eq 'Managed'} | Select-Object -Property Id
$Domains = $DomainList.Id -join '|'

$Today = Get-Date -format yyyy-MM-dd
#Reference to Upcoming Module Handling Variable Load & Multi-Login

$query=@"
let AppData = (
McasShadowItReporting
| where AppScore <= 6
| where TimeGenerated >= ago(30d)
| where AppTags !contains 'sanctioned'
| project EnrichedUserName, AppName, AppScore, AppCategory, tostring(AppTags), UploadedBytes, DownloadedBytes, TotalBytes
| extend UserName = tolower(EnrichedUserName)
| order by AppName asc, TotalBytes desc
| partition hint.strategy = native by AppName
(
    summarize Download = sum(DownloadedBytes), Upload = sum(UploadedBytes), Traffic = sum(TotalBytes) by UserName, AppName, AppScore, AppCategory, tostring(AppTags)
    | top 5 by Traffic
)
| project AppName, UserName, AppScore, AppCategory, AppTags, Traffic=format_bytes(Traffic), Download=format_bytes(Download), Upload=format_bytes(Upload)
| order by AppName asc, Traffic desc);
let ManagerData = (
IdentityInfo
| where TimeGenerated >= ago(30d)
| where IsAccountEnabled == true and AccountName != 'Guest' and UserType != 'Guest'
| where AccountUPN !contains '.onmicrosoft.com'
| where AccountUPN matches regex "($Domains)"
| summarize arg_max(TimeGenerated, *) by UserName=tolower(AccountUPN)
| project UserName, JobTitle, Department, Manager
| order by UserName asc, Department asc);
AppData
| join kind=leftouter (ManagerData) on UserName
| project AppName, AppCategory, AppScore, AppTags, Traffic, Upload, Download, UserName, JobTitle, Department, Manager
| order by AppName asc, Traffic desc
"@

Write-Host "Ingesting MCASShadowITReporting table over the last 30 days for all Apps with an AppScore <= 6, with the top 5 Users by TotalTraffic per App..."
$kqlQuery = Invoke-AzOperationalInsightsQuery -WorkspaceId $WorkspaceID -Query $query
$Results= $kqlQuery.Results
$Results = [array]$Results | Select-Object AppName, AppCategory, AppScore, AppTags, Traffic, Upload, Download, UserName, JobTitle, Department, Manager
$Results | Export-Excel "c:\temp\$Today - MCASTopAppUsers.xlsx" -TableName MCASTop5AppUsers -AutoSize