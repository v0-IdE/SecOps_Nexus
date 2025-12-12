#Reference to Upcoming Module Handling Variable Load & Multi-Login

$Today = (Get-Date -format yyyy-MM-dd)
$DomainList= Get-MgDomain | Where-Object{$_.AuthenticationType -eq 'Managed'} | Select-Object -Property Id
$Domains = $DomainList.Id -join '|'

$query = "SigninLogs
| where TimeGenerated >= ago(30d)
| extend Device = parse_json(DeviceDetail)
| extend isManaged = Device.isManaged
| extend isCompliant = Device.isCompliant
| extend operatingSystem = Device.operatingSystem
| extend DeviceName = Device.displayName
| extend deviceId = Device.deviceId
| extend trustType = Device.trustType
| extend Stat = parse_json(Status)
| extend errorCode = Stat.errorCode
| where trustType !contains 'join'
| where IsInteractive == true
| where isManaged != true
| where operatingSystem !contains 'Android' and operatingSystem !contains 'Ios' and ConditionalAccessStatus == 'success' and ResultType == 0
| summarize Logins=count() by UserPrincipalName = tolower(UserPrincipalName), tostring(operatingSystem), tostring(DeviceName), UserId, tostring(trustType), tostring(deviceId)
| project User=UserPrincipalName, OS=operatingSystem, Logins, BYODname=DeviceName, BYODid=deviceId, trustType, UserId
| order by Logins desc, UserId asc"

Write-Host "Querying summarized interactive successful sign-ins on nonMobile BYOD over 30 days"
$kqlQuery = Invoke-AzOperationalInsightsQuery -WorkspaceId $WorkspaceID -Query $query
$BYOD = [array]$kqlQuery.Results

$query = "IdentityInfo
| where TimeGenerated >= ago(30d)
| where IsAccountEnabled == true and AccountName != 'Guest' and UserType != 'Guest'
| where AccountUPN !contains '.onmicrosoft.com' and isnotempty(AccountUPN)
| where AccountUPN matches regex @'($Domains)'
| summarize arg_max(TimeGenerated, *) by UserName=tolower(AccountUPN)
| project UserName, JobTitle, Department, Manager, AccountObjectId
| order by UserName asc, Department asc, AccountObjectId"

Write-Host "Enhancing user data..."
$kqlQuery = Invoke-AzOperationalInsightsQuery -WorkspaceId $WorkspaceID -Query $query
$Managers = [array]$kqlQuery.Results

$query = "SigninLogs
| where TimeGenerated >= ago(30d)
| extend Device = parse_json(DeviceDetail)
| extend isManaged = Device.isManaged
| extend isCompliant = Device.isCompliant
| extend operatingSystem = Device.operatingSystem
| extend DeviceName = Device.displayName
| where IsInteractive == true
| where isManaged == true
| where isCompliant  == true
| project isManaged, isCompliant, operatingSystem, DeviceName, AppDisplayName, UserPrincipalName, UserId
| summarize Logins=count() by tostring(DeviceName), UserPrincipalName, UserId
| where Logins >= 50"

Write-Host "Ingesting tenant-wide sign-in logs. Building user to device mapping..."
$kqlQuery = Invoke-AzOperationalInsightsQuery -WorkspaceId $WorkspaceID -Query $query
$DeviceMapping = [array]$kqlQuery.Results

$query = "let BYOD = ( SigninLogs
| where TimeGenerated >= ago(30d)
| extend Device = parse_json(DeviceDetail)
| extend isManaged = Device.isManaged
| extend isCompliant = Device.isCompliant
| extend operatingSystem = Device.operatingSystem
| extend DeviceName = Device.displayName
| extend deviceId = Device.deviceId
| extend trustType = Device.trustType
| extend TimePeriod = datetime_add('hour', 4, TimeGenerated)
| where trustType !contains 'join'
| where IsInteractive == true
| where isCompliant != true
| where isManaged != true
| where UserPrincipalName matches regex ($Domains)
| where operatingSystem !contains 'Android' and operatingSystem !contains 'Ios' and ConditionalAccessStatus == 'success' and ResultType == 0
| project User=tolower(UserPrincipalName), OS=operatingSystem, BYODname=DeviceName, UserId, trustType, App=AppDisplayName, BYODid=deviceId, IPAddress, AuthTime=TimeGenerated, TimePeriod);
OfficeActivity
| extend User=UserId
| project-away UserId
| where IsManagedDevice == false
| where User !contains 'spadmin'
| where User matches regex ($Domains)
| project User, UserAgent, RecordType, Operation, OfficeWorkload, OfficeObjectId, SourceFileName, IPAddress=ClientIP, Event_Data, IsManagedDevice, TimeGenerated
| join kind=innerunique (BYOD) on `$left.User == `$right.User and `$left.IPAddress == `$right.IPAddress
| where TimeGenerated between (AuthTime .. TimePeriod)
| project TimeGenerated, IPAddress, User, SourceFileName, Operation, OfficeObjectId, Event_Data, OfficeWorkload, RecordType, App, UserAgent, OS, BYODname, IsManagedDevice, trustType, UserId, BYODid
| order by TimeGenerated desc, User asc"

Write-Host "Querying Office Activity on noncompliant nonmanaged devices over 30 days with 8 hour variance between signIn & activity"
$kqlQuery = Invoke-AzOperationalInsightsQuery -WorkspaceId $WorkspaceID -Query $query
$BYODOfficeActivity = [array]$kqlQuery.Results
$BYODOfficeActivity | Export-Excel "c:\temp\BYOD OfficeActivity 30d - $Today.xlsx" -TableName UserAudit -AutoSize

Connect-MgGraph -NoWelcome

Write-Host "Querying all users..."
$Users = Get-MgUser -All -Property 'UserPrincipalName', 'AccountEnabled', 'Department', 'JobTitle', 'SignInActivity', 'UserType', 'EmployeeType', 'OnPremisesSamAccountName', 'CreatedDateTime', 'LastPasswordChangeDateTime', 'EmployeeID', 'PasswordPolicies', 'Id' | Select-Object UserPrincipalName, @{N='UserId';E={$_.Id}}, AccountEnabled, Department, JobTitle, CreatedDateTime, LastPasswordChangeDateTime, UserType, EmployeeType, OnPremisesSamAccountName, EmployeeID, PasswordPolicies, @{N='LastSignInDate';E={$_.SignInActivity.LastSignInDateTime}}, @{N='LastNonInteractiveSignInDateTime';E={$_.SignInActivity.LastNonInteractiveSignInDateTime}}

#Join managers to user table
$Users = Join-Object -Left $Users -Right $Managers -LeftJoinProperty UserId,UserPrincipalName -RightJoinProperty AccountObjectId,UserName -RightProperties Manager -Type AllInLeft

#Ingest all managedDevices with all pertinent details
Write-Host "Querying all managed devices from tenant..."
$AllDevices = Get-MgDevice -All -Property EnrollmentProfileName, IsManaged, ProfileType, managementType, enrollmentType, DisplayName, AccountEnabled, ApproximateLastSignInDateTime, DeletedDateTime, OnPremisesLastSyncDateTime, DeviceOwnership, DeviceVersion, OperatingSystem, OperatingSystemVersion, registrationDateTime, DeviceId, Id, TrustType | Select-Object DisplayName, @{N='DeviceEnabled';E={$_.AccountEnabled}}, registrationDateTime, ApproximateLastSignInDateTime, OnPremisesLastSyncDateTime, @{N='managementType';E={$_.AdditionalProperties.managementType}}, @{N='enrollmentType';E={$_.AdditionalProperties.enrollmentType}}, DeviceOwnership, OperatingSystem, OperatingSystemVersion, DeviceId, Id, TrustType, ProfileType, IsManaged, EnrollmentProfileName
$ManagedDevices = Get-MgDeviceManagementManagedDevice -All | Select-Object AzureAdDeviceId, ComplianceState, DeviceEnrollmentType, @{N='ManagedDeviceName';E={$_.DeviceName}}, @{N='ManagedDeviceId';E={$_.Id}}, EnrolledDateTime, AzureAdRegistered, LastSyncDateTime, ManagedDeviceOwnerType, OperatingSystem, UserId, UserPrincipalName
#Enhance managedDevices query with status on deviceEnabled
$ManagedDevices = Join-Object -Left $ManagedDevices -Right $AllDevices -LeftJoinProperty AzureAdDeviceId -RightJoinProperty DeviceId -RightProperties DeviceEnabled -Type AllInLeft

$TempRes = @()
Write-Host "Building report details..."
foreach ($Record in $Users) {
    $DeviceName = ""
    $Device = @([pscustomobject]@{AzureAdDeviceId="";ComplianceState="";DeviceEnrollmentType="";ManagedDeviceName="";ManagedDeviceId="";EnrolledDateTime="";Imei="";IsEncrypted="";IsSupervised="";JailBroken="";LastSyncDateTime="";ManagedDeviceOwnerType="";ManagementAgent="";Manufacturer="";Model="";Meid="";OperatingSystem="";OSVersion="";PhoneNumber="";RequireUserEnrollmentApproval="";SerialNumber="";SubscriberCarrier="";UserPrincipalName="";WiFiMacAddress=""})
    $UID= $Record.UserId
    $user = ($Record.UserPrincipalName).ToLower()
    $FrequentDevice = $DeviceMapping | ?{$_.UserId -eq $UID}
    $FrequentDevice = $FrequentDevice.DeviceName
    $Devices = $ManagedDevices | ?{$_.UserId -eq $UID -and $_.ManagedDeviceOwnerType -eq "company" -and $_.OperatingSystem -match "^Windows*"}
    $DeviceName = $Devices.ManagedDeviceName
    if ($Devices) {if ($Devices[1]) {$Device = $Devices | Sort-Object -Property LastSyncDateTime | Select-Object -Last 1 } else {$Device = $Devices}}
    $TempRes += @([pscustomobject]@{User=$user;AccountEnabled=$Record.AccountEnabled;UserType=$Record.UserType;EmployeeType=$Record.EmployeeType;Title=$Record.JobTitle;Department=$Record.Department;Manager=$Record.Manager;Created=$Record.CreatedDateTime;LastPassChange=$Record.LastPasswordChangeDateTime;PasswordPolicies=$Record.PasswordPolicies;LastSignInDate=$Record.LastSignInDate;LastNonInteractiveSignInDateTime=$Record.LastNonInteractiveSignInDateTime;FrequentDevices=[string]$FrequentDevice;ManagedDevices=[string]$DeviceName;ManagedDeviceOwnerType=$Device.ManagedDeviceOwnerType;ComplianceState=$Device.ComplianceState;AzureAdRegistered=$Device.AzureAdRegistered;DeviceEnrollmentType=$Device.DeviceEnrollmentType;EnrolledDateTime=$Device.EnrolledDateTime;LastSyncDateTime=$Device.LastSyncDateTime;UserId=$UID})
}

$Enriched = Join-Object -left $BYOD -right $TempRes -LeftJoinProperty UserId,User -RightJoinProperty UserId,User -Type AllInLeft
$EnrichedFiltered = $Enriched | ?{$_.DeviceName -notmatch "(phone|phon|iPhone|android|Android)" -and $_.UserType -ne "Guest" -and $_.UserType -ne '' -and $null -ne $_.UserType -and $_.AccountEnabled -eq $true}
$EnrichedFiltered | Export-Excel "c:\temp\BYOD Successful Connections 30 day - $Today.xlsx" -TableName UserAudit -AutoSize