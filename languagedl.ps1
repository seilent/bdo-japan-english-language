#Requires -Version 5.1

$ScriptRoot = $PSScriptRoot
if (-not $ScriptRoot) {
    $ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
}

function Manage-ResourceIniFile {
    $ResourceIniPath = Join-Path -Path $ScriptRoot -ChildPath "Resource.ini"
    
    $ExpectedIniContent = @"
[SERVICE]
RES=_ID_

"@

    Write-Host "Managing Resource.ini file at: ${ResourceIniPath}" # Fixed variable reference

    if (Test-Path -Path $ResourceIniPath -PathType Leaf) {
        $CurrentContent = Get-Content -Path $ResourceIniPath -Raw -ErrorAction SilentlyContinue
        $FileIsReadOnly = $false
        try {
            $FileAttributes = Get-ItemProperty -Path $ResourceIniPath -ErrorAction Stop
            $FileIsReadOnly = $FileAttributes.IsReadOnly
        } catch {
            Write-Warning "Could not get attributes for ${ResourceIniPath}. Assuming it needs update. Error: $($_.Exception.Message)" # Fixed variable reference
        }

        if ($CurrentContent -eq $ExpectedIniContent -and $FileIsReadOnly) {
            Write-Host "Resource.ini is already correctly configured and read-only. No changes needed."
            return
        }

        Write-Host "Resource.ini found but needs update (content differs or not read-only)."
        try {
            if ($FileIsReadOnly) {
                Set-ItemProperty -Path $ResourceIniPath -Name IsReadOnly -Value $false -ErrorAction Stop
                Write-Host "Read-only attribute removed from Resource.ini."
            }
            Remove-Item -Path $ResourceIniPath -Force -ErrorAction Stop
            Write-Host "Resource.ini deleted."
        }
        catch {
            Write-Error "Error modifying or deleting existing Resource.ini: $($_.Exception.Message)"
            return
        }
    }
    else {
        Write-Host "Resource.ini not found. Will create a new one."
    }

    try {
        Write-Host "Creating new Resource.ini file..."
        Set-Content -Path $ResourceIniPath -Value $ExpectedIniContent -Encoding UTF8 -ErrorAction Stop
        Write-Host "Resource.ini created successfully."

        Write-Host "Setting Resource.ini to read-only..."
        Set-ItemProperty -Path $ResourceIniPath -Name IsReadOnly -Value $true -ErrorAction Stop
        Write-Host "Resource.ini set to read-only."
    }
    catch {
        Write-Error "Error creating or setting Resource.ini to read-only: $($_.Exception.Message)"
    }
}

$url = "https://naeu-o-dn.playblackdesert.com/UploadData/ads_files"
$downloadDirectoryName = "ads"
$downloadFileName = "languagedata_id.loc"
$VersionFilePath = Join-Path -Path $ScriptRoot -ChildPath "languageversion.txt"
$ProceedWithDownload = $false

try {
    Write-Host "Fetching content from $url to determine the remote version number..."
    $content = Invoke-RestMethod -Uri $url -ErrorAction Stop
    $remoteVersionString = $content | Select-String -Pattern 'languagedata_en\.loc\s+(\d+)' | ForEach-Object { $_.Matches.Groups[1].Value }

    if (-not $remoteVersionString) {
        Write-Error "Could not extract the version number from the URL content. Please check the URL or pattern."
        exit 1
    }
    $CurrentRemoteVersion = [int]$remoteVersionString
    Write-Host "Extracted remote version number: $CurrentRemoteVersion"

    $LocalVersion = 0
    if (Test-Path $VersionFilePath -PathType Leaf) {
        try {
            $LocalVersionContent = Get-Content -Path $VersionFilePath -Raw
            if (-not [string]::IsNullOrWhiteSpace($LocalVersionContent)) {
                $LocalVersion = [int]$LocalVersionContent
                Write-Host "Found local version in ${VersionFilePath}: $LocalVersion" # Fixed variable reference
            } else {
                 Write-Warning "${VersionFilePath} is empty. Assuming local version 0." # Fixed variable reference
                 $LocalVersion = 0
            }
        } catch {
            Write-Warning "Could not parse version from ${VersionFilePath}. Assuming local version 0. Error: $($_.Exception.Message)" # Fixed variable reference
            $LocalVersion = 0
        }
    } else {
        Write-Host "${VersionFilePath} not found. Will treat local version as 0." # Fixed variable reference
        $LocalVersion = 0
    }

    if ($CurrentRemoteVersion -gt $LocalVersion) {
        Write-Host "New version $CurrentRemoteVersion found (local version was $LocalVersion). Proceeding with download."
        $ProceedWithDownload = $true
    } else {
        Write-Host "Current local version $LocalVersion is up to date or newer than remote version $CurrentRemoteVersion. Skipping download of language file."
        $ProceedWithDownload = $false
    }

    if ($ProceedWithDownload) {
        $downloadLink = "https://naeu-o-dn.playblackdesert.com/UploadData/ads/languagedata_en/$CurrentRemoteVersion/languagedata_en.loc"
        $fullDirectoryPath = Join-Path -Path $ScriptRoot -ChildPath $downloadDirectoryName
        $fullFilePath = Join-Path -Path $fullDirectoryPath -ChildPath $downloadFileName

        if (-not (Test-Path -Path $fullDirectoryPath -PathType Container)) {
            Write-Host "Creating directory: $fullDirectoryPath"
            New-Item -ItemType Directory -Path $fullDirectoryPath -ErrorAction Stop | Out-Null
        }

        Write-Host "Downloading file from $downloadLink and saving to $fullFilePath..."
        Invoke-WebRequest -Uri $downloadLink -OutFile $fullFilePath -ErrorAction Stop
        Write-Host "File downloaded and saved successfully."

        Set-Content -Path $VersionFilePath -Value $CurrentRemoteVersion -Encoding UTF8 -ErrorAction Stop
        Write-Host "Updated ${VersionFilePath} to version $CurrentRemoteVersion." # Fixed variable reference
    }
}
catch {
    Write-Error "An error occurred during the download and version check process: $($_.Exception.Message)"
    exit 1
}

Manage-ResourceIniFile

Write-Host "Noice, done."
