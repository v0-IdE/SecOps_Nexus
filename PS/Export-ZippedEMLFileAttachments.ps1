#Secure file extract from Defender XDR Email Download. 
#Extracts a .zip file on the desktop within Windows Sandbox for evaluation or upload to others like VT
if (Test-Path -Path 'C:\Users\WDAGUtilityAccount\Desktop\*.zip') {
    if (Test-Path -Path 'C:\Temp\') {} else {New-Item -Path "C:\" -Name "temp" -ItemType "directory"}
    Move-Item -Path 'C:\Users\WDAGUtilityAccount\Desktop\*.zip' -Destination 'c:\temp\'
    $Files = dir "c:\temp\*.eml"
    foreach ($File in $Files.Name) {
        #Build full filename from list of all eml files in directory
        $EmlFilename = "C:\temp\$File"
        # Instantiate new ADODB Stream object
        $adoStream = New-Object -ComObject 'ADODB.Stream'
        # Open stream
        $adoStream.Open()
        # Load file
        $adoStream.LoadFromFile($EmlFileName)
        Write-Host "FileName: "$EmlFileName
        # Instantiate new CDO Message Object
        $cdoMessageObject = New-Object -ComObject 'CDO.Message'
        # Open object and pass stream
        $cdoMessageObject.DataSource.OpenObject($adoStream, '_Stream')
        # construct output path from current directory + attachment filename
        $exportPath = Join-Path $PWD $attachment.FileName
        foreach ($File in $cdoMessageObject.Attachments) {
            $FileName = $File.FileName
            $File.savetofile("c:\temp\$Filename")
        }
    }
}



6b5b3f20-c9bf-4d5e-ac52-db8b532c54df