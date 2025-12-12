function Edit-BulkGroup {
    param (
        [Parameter(Position = 0)]
        [Parameter(Mandatory=$true)]
        [string[]]$Objects,
        [ValidateSet("Add","Update","Remove")]
        [Parameter(Mandatory=$true)]
        [string]$Mode,
        [Parameter(Mandatory=$true)]
        [string]$Group
    )
    
    Start-ThreadJob -Name 'AllDevices' -ScriptBlock { Get-MgDeviceManagementManagedDevice | Select-Object -Property AccountEnabled, UserDisplayName, DeviceName, AzureAdDeviceId, Id, ManagedDeviceOwnerType, ComplianceState, AzureAdRegistered, EnrolledDateTime, LastSyncDateTime | ?{$_.AccountEnabled -eq $true} } | Out-Null
    Start-ThreadJob -Name 'AllUsers' -ScriptBlock {Get-MgUser -Property AccountEnabled, UserPrincipalName, Id, UserType, EmployeeType, DisplayName | Select-Object -Property AccountEnabled, UserPrincipalName, Id, UserType, EmployeeType, DisplayName | ?{$_.AccountEnabled -eq $true} } | Out-Null 
    #Check for proper usage
    if ($Objects -and $Group -and $Mode){
        Connect-MgGraph -NoWelcome
        $Result = @()

        #Ensure groupName & Id regardless of paramType
        if ($Group -like "*-*-*-*-*") {
            $GroupID = $Group
            #Ingest current GroupMembers
            $GroupMembers = (Get-MgGroupMember -GroupID $Group -All).AdditionalProperties
        }
        else {
            #Ingest current GroupMembers
            $GroupID = Get-MgGroup -Filter "DisplayName eq '$Group'" | Select-Object -Property DisplayName,Id
            $GroupMembers = (Get-MgGroupMember -GroupID $GroupID.Id -All).AdditionalProperties
        }
        #Build Add/Drop List
        if ($Mode -eq "Update") {
            #Detect Users
            if ($GroupMembers.userPrincipalName) {
                $ObjectsToAdd = $($Objects | ?{$_ -NotIn $GroupMembers.userPrincipalName})
                $ObjectsToRemove = $($GroupMembers.userPrincipalName | ?{$_ -NotIn $Objects})
            }
            #Detect Devices
            if ($GroupMembers.deviceOwnership) {
                $ObjectsToAdd = $($Objects | ?{$_ -NotIn $GroupMembers.displayName})
                $ObjectsToRemove = $($GroupMembers.displayName | ?{$_ -NotIn $Objects})
            }
            $Mode = "Updated"
        }
        if ($Mode -eq 'Add') {
            if ($GroupMembers.userPrincipalName) {
                $ObjectsToAdd = $($Objects | ?{$_ -NotIn $GroupMembers.userPrincipalName})
            }
            #Detect Devices
            if ($GroupMembers.deviceOwnership) {
                $ObjectsToAdd = $($Objects | ?{$_ -NotIn $GroupMembers.displayName})
            }
            $Mode = "Added"
        }
        if ($Mode -eq 'Remove') {
            if ($GroupMembers.userPrincipalName) {
                $ObjectsToAdd = $($Objects | ?{$_ -In $GroupMembers.userPrincipalName})
            }
            #Detect Devices
            if ($GroupMembers.deviceOwnership) {
                $ObjectsToAdd = $($Objects | ?{$_ -In $GroupMembers.displayName})
            }
            $Mode = "Removed"
        }
        $AllDevices = Receive-Job -Name 'AllDevices' -Wait -AutoRemoveJob
        $AllUsers = Receive-Job -Name 'AllUsers' -Wait -AutoRemoveJob
        #Users detected in Params
        if ($Objects -like "*@*"){
            $Type = "Users"
            if ($ObjectsToAdd -ne "" -or $ObjectsToRemove -ne "") {
                ForEach ($DisplayName in $ObjectsToRemove) {
                    $User = $AllUsers | ?{$_ -match $DisplayName}
                    if ($null -eq $User){Write-Host "$DisplayName not found or disabled";break}
                    Write-Host "Removing"$DisplayName "from $Type group:" $GroupID.DisplayName
                    Remove-MgGroupMemberByRef -GroupId $GroupID.Id -DirectoryObjectId $User.Id
                }
                ForEach ($DisplayName in $ObjectsToAdd) {
                    $User = $AllUsers | ?{$_ -match $DisplayName}
                    if ($null -eq $User){Write-Host "$DisplayName not found or disabled";break}
                    Write-Host "Adding"$DisplayName "to $Type group:" $GroupID.DisplayName
                    $Result += @([pscustomobject]@{User=$User.DisplayName;UPN=$User.UserPrincipalName;UserID=$User.Id;Group=$GroupID.DisplayName;GroupID=$GroupID.Id})
                    New-MgGroupMember -GroupId $GroupID.Id -DirectoryObjectId $User.Id
                }
            }
        }
        #Devices detected in Params
        else {
            $Type = "Devices"
            if ($ObjectsToAdd -ne "" -or $ObjectsToRemove -ne "") {
                ForEach ($DisplayName in $ObjectsToRemove) {
                    $Device = $AllDevices | ?{$_ -match $DisplayName}
                    if ($null -eq $Device){Write-Host "$DisplayName not found or disabled";break}
                    $DeviceID = Get-MgDeviceByDeviceId -DeviceId $Device.AzureAdDeviceId
                    Write-Host "Removing"$DisplayName"to $Type group:" $GroupID.DisplayName
                    Remove-MgGroupMemberByRef -GroupId $CurrentComputerGroup.Id -DirectoryObjectId $Device.Id
                }
                ForEach ($DisplayName in $ObjectsToAdd) {
                    $Device = $AllDevices | ?{$_ -match $DisplayName}
                    if ($null -eq $Device){Write-Host "$DisplayName not found or disabled";break}
                    $DeviceID = Get-MgDeviceByDeviceId -DeviceId $Device.AzureAdDeviceId
                    Write-Host "Adding"$DisplayName"to $Type group:" $GroupID.DisplayName
                    $Result += @([pscustomobject]@{Device=$DisplayName;deviceId=$DeviceID.Id;Owner=$Device.UserDisplayName;Group=$GroupID.DisplayName;GroupID=$GroupID.Id})
                    New-MgGroupMember -GroupId $CurrentComputerGroup.Id -DirectoryObjectId $Device.Id
                }
            }
        }
        if (!$ObjectsToAdd -and !$ObjectsToRemove){
            Write-Host "No changes to group required"
        }
        else {
            Write-Host "$Type $Mode to Group: [$($GroupID.DisplayName)]"
            $Result | Format-Table
        }
    }
    else {
        Write-Host ""
        Write-Host ""
        Write-Host ""
        Write-Host "Required parameters not detected:"
        Write-Host "Note: Always start with the devices/users in the first parameter. Mode can be Add, Update, or Remove. Update removes all members not specified in the Object parameter."
        Write-Host "Example: Edit-BulkGroup <DeviceNames/UserPrincipalNames> -Group <Group DisplayName or GroupID> -Mode Remove"
        Write-Host "Overwriting Group with Users: Edit-BulkGroup -Objects First.Last@domain.com,Other.User@domain.com -Group xxxxxx-xxx-xxxx-xxx-xxxxx -Mode Update"
        Write-Host "Adding Devices: Edit-BulkGroup -Objects computer1,computer2,computer3 -Group MyDeviceGroup -Mode Add"
    }
}