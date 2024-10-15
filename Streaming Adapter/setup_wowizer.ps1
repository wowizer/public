# Set environment variables for Wowizer
param (
    [string]$tenantID,
    [string]$QlickIp,
    [string]$zipFile
)

if (-not $tenantID -or -not $QlickIp -or -not $zipFile) {
    Write-Host "Please provide Unique Stream ID (tenantID), Qlick IP and cert.zip path."
    exit 1
}

$elevated = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($elevated -ne 'True') {
    Write-Output "You are not Administrator User. You need to Run PowerShell Script in as 'Windows PowerShell with Administrator' to setup wowizer realtime"
    break;
} else {

    [Environment]::SetEnvironmentVariable("QLIK_LOGS_ROOT_PATH", "C:\ProgramData\Qlik\Sense\Log", [System.EnvironmentVariableTarget]::Machine)
    [Environment]::SetEnvironmentVariable("WOW_Ingestion_ID", "$tenantID", [System.EnvironmentVariableTarget]::Machine)

    $HealthDataDownloadURL = "https://github.com/wowizer/public/raw/wowizer-documents/HealthData/v3/HealthData_Wowizer_v3.zip"
    $winlogbeatDownloadURL = "https://github.com/wowizer/public/raw/wowizer-documents/Streaming%20Adapter/Winlogbeat_v2.zip"
    $filebeatDownloadURL = "https://github.com/wowizer/public/raw/wowizer-documents/Streaming%20Adapter/filebeat_wowizer_v2.zip"
	
    # Create the wowizer directory
	if (-not (Test-Path "C:\wowizer")) {
		Write-Host "Creating wowizer directory on C drive..."
		New-Item -ItemType Directory -Path "C:\wowizer"
	}

    # Download and unzip HealthData inside wowizer directory
    Write-Output "Downloading HealthData_Wowizer_v3.zip file"
    Invoke-WebRequest -Uri $HealthDataDownloadURL -OutFile "C:\wowizer\HealthData_Wowizer_v3.zip"

    try {
        Expand-Archive -Path "C:\wowizer\HealthData_Wowizer_v3.zip" -DestinationPath "C:\wowizer\HealthData_Wowizer_v3"
        Remove-Item -Path "C:\wowizer\HealthData_Wowizer_v3.zip" -Force
        # Update Qlik Sense Server IP
        $filePath = "C:\wowizer\HealthData_Wowizer_v3\wowizer_healthcheck.bat"
        (Get-Content $filePath) | ForEach-Object { $_ -replace "<YOUR QLIK HOST IP>", "$QlickIp" } | Set-Content $filePath
        Write-Output "Download completed"
    } catch {
        Write-Error "Error expanding HealthData archive: $_"
        exit 1
    }

    # Download and unzip Winlogbeat inside wowizer directory
    Write-Output "Downloading Winlogbeat_v2.zip file"
    Invoke-WebRequest -Uri $winlogbeatDownloadURL -OutFile "C:\wowizer\Winlogbeat_v2.zip"

    try {
        Expand-Archive -Path "C:\wowizer\Winlogbeat_v2.zip" -DestinationPath "C:\wowizer\Winlogbeat_v2"
        Remove-Item -Path "C:\wowizer\Winlogbeat_v2.zip" -Force
        Write-Output "Download completed"
    } catch {
        Write-Error "Error expanding Winlogbeat archive: $_"
        exit 1
    }

    # Download and unzip Filebeat inside wowizer directory
    Write-Output "Downloading filebeat_wowizer_v2.zip file"
    Invoke-WebRequest -Uri $filebeatDownloadURL -OutFile "C:\wowizer\filebeat_wowizer_v2.zip"

    try {
        Expand-Archive -Path "C:\wowizer\filebeat_wowizer_v2.zip" -DestinationPath "C:\wowizer\filebeat_wowizer_v2"
        Remove-Item -Path "C:\wowizer\filebeat_wowizer_v2.zip" -Force
        Write-Output "Extracting Cert zip file into filebeat"
        Expand-Archive -Path $zipFile -DestinationPath "C:\wowizer\filebeat_wowizer_v2\cert" -Force
        # Update certificate filename
        $filebeatymlPath = "C:\wowizer\filebeat_wowizer_v2\filebeat.yml"
        (Get-Content $filebeatymlPath) | ForEach-Object { $_ -replace "<tenant>", "$tenantID" } | Set-Content $filebeatymlPath
        Write-Output "Download completed"
    } catch {
        Write-Error "Error expanding Filebeat archive: $_"
        exit 1
    }

    # Start HealthData Service
    Write-Output "Starting healthcheck installation....."
    cd "C:\wowizer\HealthData_Wowizer_v3"
    .\healthcheckstart.bat -ArgumentList "/silent /other-parameters"
    Start-Sleep -Seconds 30
    Write-Output "Healthcheck installation completed"
    Start-Sleep -Seconds 10
    # Check healthcheckdata.txt
    $directoryPath = "C:\wowizer\HealthData_Wowizer_v3\"
    $filePath1 = Join-Path -Path $directoryPath -ChildPath "healthcheckdata.txt"

    if (Test-Path -Path $filePath1 -PathType Leaf) {
        Write-Host "The file $filePath1 exists in the directory."
        Write-Output "Starting winlogbeat installation....."
        # Install Winlogbeat and Filebeat
        & "C:\wowizer\Winlogbeat_v2\install-service-winlogbeat.ps1"
        Start-Service -Name "Wowizer Winlogbeat"
        Start-Sleep -Seconds 10
        Write-Output "Starting filebeat installation....."
        & "C:\wowizer\filebeat_wowizer_v2\install-service-filebeat.ps1"
        Start-Service -Name "Wowizer Filebeat"
        Start-Sleep -Seconds 10
        Get-Service "Wowizer HealthCheck"
        Get-Service "Wowizer Winlogbeat"
        Get-Service "Wowizer Filebeat"
        Start-Sleep -Seconds 10
        Write-Host "Installation and service start completed."
        exit 0
    } else {
        Write-Host "The file $filePath1 does not exist in the directory."
        exit 0
    }
}