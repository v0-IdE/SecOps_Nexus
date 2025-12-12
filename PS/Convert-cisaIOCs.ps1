#Takes a STIX.json file from CISA.gov and exports IOCs as Block/BlockAndRemediate in Defender XDR formatting for bulk upload.

function Convert-STIX2Defender {
    param (
        $StixFile,
        $Title, #Title of the IOC. Required
        $Description, #Information about it. Required
        $RecommendedActions, #TI indicator alert recommended actions. Optional
        $Severity, #Informational, Low, Medium, High. Optional
        $Catagory, #MITRE Tactic Categories involved (e.g. Credential Access, Execution). Optional
        $Alert #True, False. Required
    )
    $Export=@()
    $Ingest = (Get-Content -Raw $File | ConvertFrom-Json -AsHashtable).objects.pattern
    Switch -regex ($Ingest){
        '(?<IP>\d+\.\d+\.\d+\.\d+)' { $Export+= @([pscustomobject]@{IndicatorType='IpAddress';IndicatorValue=$matches.IP;ExpirationTime='';Action='Block';Severity=$Severity;Title=$Title;Description=$Description;RecommendedActions=$RecommendedActions;RbacGroups='';Category=$Category;MitreTechniques='';GenerateAlert=$Alert}) }
        '(?<md5>[a-fA-F0-9]{32})' { $Export+= @([pscustomobject]@{IndicatorType='FileMd5';IndicatorValue=$matches.md5;ExpirationTime='';Action='BlockAndRemediate';Severity=$Severity;Title=$Title;Description=$Description;RecommendedActions=$RecommendedActions;RbacGroups='';Category=$Category;MitreTechniques='';GenerateAlert=$Alert}) }
        '(?<sha1>[a-fA-F0-9]{40})' { $Export+= @([pscustomobject]@{IndicatorType='FileSha1';IndicatorValue=$matches.sha1;ExpirationTime='';Action='BlockAndRemediate';Severity=$Severity;Title=$Title;Description=$Description;RecommendedActions=$RecommendedActions;RbacGroups='';Category=$Category;MitreTechniques='';GenerateAlert=$Alert}) }
        '(?<sha256>[a-fA-F0-9]{64})' { $Export+= @([pscustomobject]@{IndicatorType='FileSha256';IndicatorValue=$matches.sha256;ExpirationTime='';Action='BlockAndRemediate';Severity=$Severity;Title=$Title;Description=$Description;RecommendedActions=$RecommendedActions;RbacGroups='';Category=$Category;MitreTechniques='';GenerateAlert=$Alert}) }
        '(?<url>http(s\:\/\/|\:\/\/).+)' { $Export+= @([pscustomobject]@{IndicatorType='Url';IndicatorValue=$matches.url;ExpirationTime='';Action='Block';Severity=$Severity;Title=$Title;Description=$Description;RecommendedActions=$RecommendedActions;RbacGroups='';Category=$Category;MitreTechniques='';GenerateAlert=$Alert}) }
        default {
            $DomainName = $switch.current.Split("'") | Select-Object -Skip 1 -First 1
            $Export += @([pscustomobject]@{IndicatorType='DomainName';IndicatorValue=$DomainName;ExpirationTime='';Action='Block';Severity=$Severity;Title=$Title;Description=$Description;RecommendedActions=$RecommendedActions;RbacGroups='';Category=$Category;MitreTechniques='';GenerateAlert=$Alert}) 
        }
    }
    $Export | Sort-Object -Property IndicatorType -Descending | Export-csv "$Title - IOCs.csv"
}
