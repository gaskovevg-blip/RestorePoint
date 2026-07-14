# Требуем запуск от администратора
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Warning "Этот скрипт требует запуска от имени администратора."


    # Создаём задачу в планировщике для автозапуска с правами администратора
    $TaskName = "CreateRestorePointWithEnable"
    $ScriptPath = $MyInvocation.MyCommand.Definition


    # Проверяем, существует ли уже задача
    $ExistingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($ExistingTask) {
        Write-Host "Задача '$TaskName' уже существует в планировщике." -ForegroundColor Yellow
    } else {
        # Создаём новую задачу
        $Action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$ScriptPath`""
        $Trigger = New-ScheduledTaskTrigger -AtStartup
        $Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RunOnlyIfNetworkAvailable $false
        $Principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

        Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Settings $Settings -Principal $Principal -Force

        Write-Host "Автозапуск настроен: скрипт будет запускаться при старте системы с правами администратора." -ForegroundColor Green
    }

    exit 1
}

Write-Host "Проверка статуса защиты системы..." -ForegroundColor Yellow

# Проверяем, включена ли защита системы для диска C:
$isProtectionEnabled = (Get-ComputerRestore -Drive "C:\").Enabled

if (-not $isProtectionEnabled) {
    Write-Host "Защита системы выключена. Попытка включить..." -ForegroundColor Yellow

    # Включаем защиту системы для диска C:
    try {
        Enable-ComputerRestore -Drive "C:\"
        Write-Host "Защита системы успешно включена для диска C:\." -ForegroundColor Green
    }
    catch {
        Write-Error "Не удалось включить защиту системы: $($_.Exception.Message)"
        exit 1
    }

    # Устанавливаем выделение 10 % дискового пространства для точек восстановления
    $regPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore"
    if (-not (Test-Path $regPath)) {
        New-Item -Path $regPath -Force | Out-Null
    }
    Set-ItemProperty -Path $regPath -Name "DiskPercent" -Value 10 -Type DWord
    Write-Host "Установлено выделение 10% дискового пространства для точек восстановления." -ForegroundColor Green
}
else {
    Write-Host "Защита системы уже включена." -ForegroundColor Green
}

# Формируем описание точки восстановления с текущей датой
$currentDate = Get-Date -Format "dd.MM.yyyy"
$description = "$currentDate ИМАНГО"
Write-Host "Создание точки восстановления: '$description'" -ForegroundColor Cyan

# Создаём точку восстановления
try {
    Checkpoint-Computer -Description $description -RestorePointType "MODIFY_SETTINGS"
    Write-Host "Точка восстановления успешно создана: $description" -ForegroundColor Green
}
catch {
    # Проверяем ограничение 24 часа
    if ($_.Exception.Message -like "*1440 minutes*") {
        Write-Warning "Не удалось создать точку восстановления: последняя точка создана менее 24 часов назад (ограничение Windows)."
    }
    else {
        Write-Error "Ошибка при создании точки восстановления: $($_.Exception.Message)"
    }
}

Write-Host "Операция завершена." -ForegroundColor White
