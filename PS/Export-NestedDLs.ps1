#Install ExchangeOnlineManagement if missing
if (Get-InstalledModule -Name exchangeonlinemanagement -MinimumVersion 3.2.0 -ErrorAction SilentlyContinue) {}
else { 
    Uninstall-Module ExchangeOnlineManagement -Force -AllVersions -ErrorAction SilentlyContinue
    Install-Module ExchangeOnlineManagement -SkipPublisherCheck -Force -Confirm:$false
}

Write-Host "Connecting to Exchange Online..."
Connect-ExchangeOnline -ShowBanner:$false

#Pull in all Distribution Lists & iterate through each, looking for external contacts mixed into DLs, empty groups, and nested DLs
$Today = (Get-Date -format yyyy-MM-dd)
$DLs = Get-DistributionGroup -filter "RecipientType -eq 'MailUniversalDistributionGroup'" -ResultSize 10000
$NestedDLs= @()
$ZeroGroups = @()
$ExternalGroups = @()
$i=0
$e=0
$m=0
$z=0
$n=0
$topScore=0
foreach ($Object in $DLs) {
    $i++
    $newtop='MaxNest'
    $Members = Get-DistributionGroupMember -Identity $Object.GUID
    $NestedGroups = $Members | ?{$_.RecipientType -eq "MailUniversalDistributionGroup"}
    $DistroUsers = $Members | ?{$_.RecipientType -eq "UserMailbox"}
    $ExternalUsers = $Members.ExternalEmailAddress -replace ("SMTP:","") | ?{$_ -ne ''}
    $ExternalEmail = $ExternalUsers -join "','"
    $InternalUsers = $DistroUsers.PrimarySmtpAddress -join "','"
    if ($ExternalUsers.count -gt 0) {
        if ($DistroUsers.count -gt 0) {
            $e++
            $m++
            Write-host "[$i/$($DLs.count)]- Empty: [$z] Mixed: [$m] External: [$e] Nested: [$n] $newtop`: [$topscore] | DL: $($Object.PrimarySmtpAddress) | Discovered: Mixed [Internal/External] Contacts: [$($DistroUsers.count)/$($ExternalUsers.count)]";$ExternalGroups += @([PSCustomObject]@{ParentSmtp=$Object.PrimarySmtpAddress;InternalExternalMixed='True';External=$ExternalUsers.count;Internal=$DistroUsers.count;ManagedBy=[string]$Object.ManagedBy;Description=[string]$Object.Description;InternalOnly=$Object.RequireSenderAuthenticationEnabled;InternalUsers="'"+$InternalUsers+"'";ExternalUsers="'"+$ExternalEmail+"'"})
        }
        else {
            $e++
            $ExternalGroups += @([PSCustomObject]@{ParentSmtp=$Object.PrimarySmtpAddress;InternalExternalMixed='False';External=$ExternalUsers.count;Internal='0';ManagedBy=[string]$Object.ManagedBy;Description=[string]$Object.Description;InternalOnly=$Object.RequireSenderAuthenticationEnabled;InternalUsers='';ExternalUsers="'"+$ExternalEmail+"'"})
        }
    }
    if ($NestedGroups.count -gt $topScore){$topscore=$NestedGroups.count;$newtop='*MaxNest*'}
    if ($Members.count -lt 1 -or !($Members)) {$z++;$ZeroGroups += @([PSCustomObject]@{Name=$Object.DisplayName;SMTPAddress=$Object.PrimarySmtpAddress})}
    if ($NestedGroups.count -gt 1) {$NestedGroupName = $NestedGroups.DisplayName -join "','";$NestedGroupSMTP = $NestedGroups.PrimarySmtpAddress -join "','"} else {$NestedGroupName = $NestedGroups.DisplayName;$NestedGroupSMTP = $NestedGroups.PrimarySmtpAddress}
    if ($NestedGroups) {$n++;Write-host "[$i/$($DLs.count)]- Empty: [$z] Mixed: [$m] External: [$e] Nested: [$n] $newtop`: [$topscore] | DL: $($Object.PrimarySmtpAddress) | Discovered: [$($NestedGroups.count)] Nested DLs: '$($NestedGroupSMTP)'";$NestedDLs += @([PSCustomObject]@{ParentSMTP=$Object.PrimarySmtpAddress;ManagedBy=[string]$Object.ManagedBy;Description=[string]$Object.Description;InternalOnly=$Object.RequireSenderAuthenticationEnabled;ParentDLUsers=$DistroUsers.count;NestCount=$NestedGroups.count;NestedSMTP="'"+$NestedGroupSMTP+"'"})}
}
#Discovery summary
Write-Host "[$z] Empty DLs - Deletion Recommended"
Write-Host "[$m] Mixed Contact DLs - SRS may cause unreliable external delivery based on Receiver's DMARC configuration. ARC seal can help ensure authenticity."
Write-Host "[$n] Nested DLs - Increased Storage Utilization. Note: If RequireSenderAuthenticationEnabled:false also increases Blast Radius Risk"
Write-Host "[$e] External DLs"
Write-Host "[$i] Total DLs"

#Merge Nested & External/Internal Mixed groupings for maximum risk.
$DLMatches = $NestedDLs | ?{($_.ParentSmtp).toLower() -in ($ExternalGroups.ParentSmtp).toLower()}
$NewMatch = Join-Object -left $DLMatches -right $ExternalGroups -LeftJoinProperty ParentSmtp -RightJoinProperty ParentSmtp -Type AllInLeft -RightProperties InternalExternalMixed, External, Internal, InternalUsers, ExternalUsers
$NewMatch = $NewMatch | ?{$_.InternalExternalMixed -eq 'True'}

#Export multi-report
$NestedDLs | Export-Excel "c:\temp\$Today-NestedandNullDLs.xlsx" -TableName 'NestedDLs' -AutoSize -WorksheetName 'NestedDLs'
$ZeroGroups | Export-Excel "c:\temp\$Today-NestedandNullDLs.xlsx" -TableName 'NullGroups' -AutoSize -WorksheetName 'NullGroups'
$ExternalGroups | Export-Excel "c:\temp\$Today-NestedandNullDLs.xlsx" -TableName 'ExternalGroups' -AutoSize -WorksheetName 'ExternalGroups'
$NewMatch | Export-Excel "c:\temp\$Today-NestedandNullDLs.xlsx" -TableName 'NestedandMixed' -AutoSize -WorksheetName 'NestedandMixed'