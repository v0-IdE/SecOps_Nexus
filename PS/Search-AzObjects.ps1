function Search-AzObjects {
    param (
        $ObjectList,
        $WorkspaceID
    )

    #Build Device-mapping off 50+ hits over 30 days
    $query = @"
let Identity = (IdentityInfo
| where TimeGenerated >= ago(30d)
| where IsAccountEnabled == true and AccountName !contains 'Guest' and UserType != 'Guest' and AccountUPN !contains '.onmicrosoft.com'
| summarize arg_max(TimeGenerated, *) by UserName=tolower(AccountUPN)
| project UserId=AccountObjectId, Created=AccountCreationTime, UserName, Title=JobTitle, Department, Manager, EmployeeId, GroupMembership, RiskState, RiskLevel, BlastRadius 
| order by Username asc, Department asc);
let Offices = (_GetWatchlist('Offices')
| extend FixedIP = split(trim("'",ipCIDRRanges),"','")
| mv-expand FixedIP
| extend CIDRList = tostring(FixedIP)
| project Site=NamedLocation, CIDRList, CityO=City, StateO=State, CountryO=Country, LatitudeO=Latitude, LongitudeO=Longitude);
let VPNs = (_GetWatchlist('VPN')
| extend FixedIP = split(trim("'",CIDR),"','")
| mv-expand FixedIP
| extend CIDRList = tostring(FixedIP)
| project CIDRLIst, Cat=Cato_Region);
let Merged = (Offices
| union (VPNs)
| extend VPN = coalesce(Cato, 'Office')
| extend Office = coalesce(Site, 'VPN')
| project-away Cato, Site
| project-reorder Office, VPN, CIDRList);
SigninLogs
| where TimeGenerated >= ago(30d) and UserType != 'Guest' and UserPrincipalName !contains '.onmicrosoft.com' and ResultType == 0
| extend Device = parse_json(DeviceDetail)
| extend isManaged = tostring(Device.isManaged)
| extend isCompliant = tostring(Device.isCompliant)
| extend operatingSystem = tostring(Device.operatingSystem)
| extend DeviceName = tostring(Device.displayName)
| extend deviceId = tostring(Device.deviceId)
| extend trustType = tostring(Device.trustType)
| extend Loc = parse_json(LocationDetails)
| extend CityS = tostring(Loc.City)
| extend StateS = tostring(Loc.State)
| extend CountryS = tostring(Loc.Country)
| extend LatS = tostring(Loc.Latitude)
| extend LongS = tostring(Loc.Longitude)
| where UserPrincipalName matches regex "($ObjectList)" or UserId matches regex "($ObjectList)" or DeviceName matches regex "($ObjectList)"
| evaluate ipv4_lookup(Merged, IPAddress, CIDRLIst, return_unmatched = true)
| extend City = coalesce(CityO, CityS, '')
| extend State = coalesce(StateO, StateS, '')
| extend Country = coalesce(CountryO, CountryS, '')
| extend Latitude = coalesce(LatitudeO, LatS, '')
| extend Longitude = coalesce(LongitudeO, LongS, '')
| summarize Logins=count() by User=tolower(UserPrincipalName), DeviceName, IPAddress, UserId, IsManaged, isCompliant, operatingSystem, trustType, Office, VPN, City, State, Country, Latitude, Longitude
| join kind=leftouter (Identity) on UserId
| project-reorder Logins, User, Title, Department, Manager, IP=IPAddress, DeviceName, OS=operatingSystem, Compliant=isCompliant, Managed=isManaged, Trust=trustType, Office, VPN, City, State, Country, Latitude, Longitude, GroupMembership, RiskState, RiskLevel, BlastRadius, Created, EmployeeId, UserId
| order by Logins
"@
    [array]$kqlQuery = Invoke-AzOperationalInsightsQuery -WorkspaceId $WorkspaceID -Query $query
    $Result = $kqlQuery.Results

    #Enhance IP hits
    #foreach ($IP in $MappedIPs){
    #    $isp_name = Invoke-RestMethod -Method Get -Uri "ipinfo.io/$($IP)"
    #    $IPResults += @([pscustomobject]@{IP=$IP;isp_name=$isp_name.org;city=$isp_name.city;region=$isp_name.region;country=$isp_name.country})
    #}

    #Totals & Unique Counts
    $UniqueIPs = $Result | Sort-Object -Property IPAddress -Unique
    $Devices = $Result | Sort-Object -Property DeviceName -Unique
    $Logins = ($Result | Measure-Object -Property Logins -Sum).Sum
    
    #Output results
    if ($Result) {
        Write-Host "Summarized Logins:"
        $Result | Format-Table
        Write-Host "[$Logins] Logins over [$($Devices.count)] Devices, Spanning [$($UniqueIPs.count)] IP addresses over 30 days"         
    }
}