
$Today = (Get-Date -format yyyy-MM-dd)
#AppId from App Registered with MgGraph permissions, Password is AppSecret
$global:SecuredCredential = (New-Object System.Management.Automation.PsCredential($AppID, $SecuredPassword))
Connect-MgGraph -tenantId $TenantId -ClientSecretCredential $SecuredCredential

$LocationExport = Get-MgIdentityConditionalAccessNamedLocation

$NamedLocations = @()
foreach ($Location in $LocationExport) {
    $NamedLocations += @([pscustomobject]@{DisplayName=$Location.DisplayName;CreatedDateTime=$Location.CreatedDateTime;ModifiedDateTime=$Location.ModifiedDateTime;Trusted=$Location.AdditionalProperties.isTrusted;ipRanges=$Location.AdditionalProperties.ipRanges.cidrAddress;Id=$Location.Id;countriesAndRegions=[string]$Location.AdditionalProperties.countriesAndRegions;includeUnknownCountriesAndRegions=$Location.AdditionalProperties.includeUnknownCountriesAndRegions;countryLookupMethod=$Location.AdditionalProperties.countryLookupMethod})
}

$Sites = $NamedLocations | Sort-Object -Property DisplayName | ?{$_.Trusted -eq $true}

$NamedPrivates = @()
$NamedPublics = @()
$NamedBackup = @()
foreach ($Location in $NamedLocations) {
    #If it's a private IP address, just back it up.
    $location.DisplayName
    if ([string]$Location.ipRanges -Match "(^127\.|^192\.168\.|^10\.|^172\.1[6-9]\.|^172\.2[0-9]\.|^172\.3[0-1]\.)") {
        if ($Location.ipRanges[1]){
            foreach ($Range in $Location.ipRanges){
                #Going to need to rewrite this to pull the positional parameter from the foreach
                $NamedPrivates += @([pscustomobject]@{DisplayName=$Location.DisplayName;CreatedDateTime=$Location.CreatedDateTime;ModifiedDateTime=$Location.ModifiedDateTime;Trusted=$Location.Trusted;ipRanges=$Range;Id=$Location.Id;countriesAndRegions=$Location.countriesAndRegions;includeUnknownCountriesAndRegions=$Location.includeUnknownCountriesAndRegions;countryLookupMethod=$Location.countryLookupMethod})            
                $NamedBackup += @([pscustomobject]@{DisplayName=$Location.DisplayName;CreatedDateTime=$Location.CreatedDateTime;ModifiedDateTime=$Location.ModifiedDateTime;Trusted=$Location.Trusted;ipRanges=$Range;Id=$Location.Id;countriesAndRegions=$Location.countriesAndRegions;includeUnknownCountriesAndRegions=$Location.includeUnknownCountriesAndRegions;countryLookupMethod=$Location.countryLookupMethod})            
            }
        }
        else {
            $NamedBackup += @([pscustomobject]@{DisplayName=$Location.DisplayName;CreatedDateTime=$Location.CreatedDateTime;ModifiedDateTime=$Location.ModifiedDateTime;Trusted=$Location.Trusted;ipRanges=$Location.ipRanges;Id=$Location.Id;countriesAndRegions=$Location.countriesAndRegions;includeUnknownCountriesAndRegions=$Location.includeUnknownCountriesAndRegions;countryLookupMethod=$Location.countryLookupMethod})            
            $NamedPrivates += @([pscustomobject]@{DisplayName=$Location.DisplayName;CreatedDateTime=$Location.CreatedDateTime;ModifiedDateTime=$Location.ModifiedDateTime;Trusted=$Location.Trusted;ipRanges=$Location.ipRanges;Id=$Location.Id;countriesAndRegions=$Location.countriesAndRegions;includeUnknownCountriesAndRegions=$Location.includeUnknownCountriesAndRegions;countryLookupMethod=$Location.countryLookupMethod})            
        
        }
    }
    #Filtered PublicIPs list, pull public IP address info for ISP
    else {
        if ($Location.ipRanges[1]){
            foreach ($Range in $Location.ipRanges){
                $NamedPublics += @([pscustomobject]@{DisplayName=$Location.DisplayName;CreatedDateTime=$Location.CreatedDateTime;ModifiedDateTime=$Location.ModifiedDateTime;Trusted=$Location.Trusted;ipRanges=$Range;Id=$Location.Id;countriesAndRegions=$Location.countriesAndRegions;includeUnknownCountriesAndRegions=$Location.includeUnknownCountriesAndRegions;countryLookupMethod=$Location.countryLookupMethod})            
                $NamedBackup += @([pscustomobject]@{DisplayName=$Location.DisplayName;CreatedDateTime=$Location.CreatedDateTime;ModifiedDateTime=$Location.ModifiedDateTime;Trusted=$Location.Trusted;ipRanges=$Range;Id=$Location.Id;countriesAndRegions=$Location.countriesAndRegions;includeUnknownCountriesAndRegions=$Location.includeUnknownCountriesAndRegions;countryLookupMethod=$Location.countryLookupMethod})            
            }
        }
        else {
            $NamedPublics += @([pscustomobject]@{DisplayName=$Location.DisplayName;CreatedDateTime=$Location.CreatedDateTime;ModifiedDateTime=$Location.ModifiedDateTime;Trusted=$Location.Trusted;ipRanges=$Location.ipRanges;Id=$Location.Id;countriesAndRegions=$Location.countriesAndRegions;includeUnknownCountriesAndRegions=$Location.includeUnknownCountriesAndRegions;countryLookupMethod=$Location.countryLookupMethod})            
            $NamedBackup += @([pscustomobject]@{DisplayName=$Location.DisplayName;CreatedDateTime=$Location.CreatedDateTime;ModifiedDateTime=$Location.ModifiedDateTime;Trusted=$Location.Trusted;ipRanges=$Location.ipRanges;Id=$Location.Id;countriesAndRegions=$Location.countriesAndRegions;includeUnknownCountriesAndRegions=$Location.includeUnknownCountriesAndRegions;countryLookupMethod=$Location.countryLookupMethod})            
        }
    }
}

$NamedRemovals = $NamedLocations | ?{$_.Id -in $NamedPrivates.Id}
$NamedBackup | Export-Excel c:\temp\$Today-NamedLocationsBackup.xlsx -TableName "NamedLocations" -AutoSize