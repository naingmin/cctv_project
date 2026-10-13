# Runs elevated (UAC). Creates the startup task, restarts the backend
# through it, and records the result in logs\install.log.
Start-Transcript -Path 'C:\Users\user\Desktop\Project\server\logs\install.log' -Force | Out-Null

$ErrorActionPreference = 'Continue'

schtasks /Create /TN "CCTV Backend" /TR "C:\Users\user\Desktop\Project\server\start_backend.bat" /SC ONSTART /RU SYSTEM /RL HIGHEST /F

# Stop any manually started instances so the task owns the server.
Get-CimInstance Win32_Process -Filter "Name='python.exe'" |
    Where-Object { $_.CommandLine -match 'uvicorn' } |
    ForEach-Object { Write-Host "stopping $($_.ProcessId)"; Stop-Process -Id $_.ProcessId -Force }

Start-Sleep -Seconds 2

schtasks /Run /TN "CCTV Backend"
Start-Sleep -Seconds 10

try {
    $r = Invoke-WebRequest -Uri 'http://localhost:8000/health' -UseBasicParsing -TimeoutSec 5
    Write-Host "HEALTH: $($r.Content)"
} catch {
    Write-Host "HEALTH FAILED: $($_.Exception.Message)"
    Get-Content 'C:\Users\user\Desktop\Project\server\logs\backend.log' -Tail 20
}

schtasks /Query /TN "CCTV Backend" /FO LIST

Stop-Transcript | Out-Null
