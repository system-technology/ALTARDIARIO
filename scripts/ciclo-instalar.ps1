# Registra (o quita) las tareas programadas de Windows que mantienen vivo el ciclo autónomo.
#
#   .\scripts\ciclo-instalar.ps1                 instala las tres tareas (plataforma, producto, auditor)
#   .\scripts\ciclo-instalar.ps1 -Quitar         las elimina
#   .\scripts\ciclo-instalar.ps1 -Repo D:\ruta   checkout desde el que corre el supervisor
#
# Qué hace cada tarea: al iniciar sesión en Windows lanza el proceso correspondiente en una
# ventana oculta y, si el proceso muere, lo relanza (hasta 3 veces, cada minuto). No necesita
# administrador: corre con tu usuario. El PC tiene que estar encendido y con la sesión iniciada.
#
# Tareas:
#   AltarDiario-Ciclo-plataforma -> node scripts\ciclo.mjs plataforma
#   AltarDiario-Ciclo-producto   -> node scripts\ciclo.mjs producto
#   AltarDiario-Ciclo-auditor    -> node scripts\auditor.mjs
#
# Cómo arrancar:
#   Start-ScheduledTask -TaskName AltarDiario-Ciclo-plataforma
#   Start-ScheduledTask -TaskName AltarDiario-Ciclo-producto
#   Start-ScheduledTask -TaskName AltarDiario-Ciclo-auditor
#
# Cómo parar:
#   Stop-ScheduledTask -TaskName AltarDiario-Ciclo-plataforma
#   Stop-ScheduledTask -TaskName AltarDiario-Ciclo-producto
#   Stop-ScheduledTask -TaskName AltarDiario-Ciclo-auditor
#   O crear el fichero de freno: New-Item <sesiones>\STOP  (se reanuda borrándolo)
#
# Requisitos del checkout (-Repo): en `main` y limpio, con `npm ci` hecho en tools\roadmap-mcp.
# Freno de emergencia: crear el fichero  <sesiones>\STOP  (se reanuda borrándolo).
param(
  [string]$Repo = 'D:\Projects\AltarDiario\ALTARDIARIO',
  [switch]$Quitar
)
$ErrorActionPreference = 'Stop'
$carriles = @('plataforma', 'producto', 'auditor')

if ($Quitar) {
  foreach ($c in $carriles) {
    $n = "AltarDiario-Ciclo-$c"
    if (Get-ScheduledTask -TaskName $n -ErrorAction SilentlyContinue) { Unregister-ScheduledTask -TaskName $n -Confirm:$false; "Quitada: $n" } else { "No existía: $n" }
  }
  return
}

$node = (Get-Command node -ErrorAction Stop).Source
foreach ($f in @('scripts\ciclo.mjs', 'scripts\ciclo.config.json', 'scripts\auditor.mjs', 'ownership.json')) {
  if (-not (Test-Path (Join-Path $Repo $f))) { throw "Falta $f en $Repo (¿está en main y al día?)" }
}
if (-not (Test-Path (Join-Path $Repo 'tools\roadmap-mcp\node_modules'))) { throw "Falta npm ci en $Repo\tools\roadmap-mcp" }
$rama = (git -C $Repo rev-parse --abbrev-ref HEAD).Trim()
if ($rama -ne 'main') { throw "El checkout $Repo está en '$rama', debe estar en main" }
if ((git -C $Repo status --porcelain)) { throw "El checkout $Repo tiene cambios sin commitear" }

foreach ($c in $carriles) {
  $n = "AltarDiario-Ciclo-$c"
  if ($c -eq 'auditor') {
    $accion = New-ScheduledTaskAction -Execute $node -Argument "scripts\auditor.mjs" -WorkingDirectory $Repo
    $cmdStr = "scripts\auditor.mjs"
  } else {
    $accion = New-ScheduledTaskAction -Execute $node -Argument "scripts\ciclo.mjs $c" -WorkingDirectory $Repo
    $cmdStr = "scripts\ciclo.mjs $c"
  }
  $disparador = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
  $ajustes = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable `
    -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew
  $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited
  Register-ScheduledTask -TaskName $n -Action $accion -Trigger $disparador -Settings $ajustes -Principal $principal -Force | Out-Null
  "Instalada: $n  ->  $node $cmdStr   (en $Repo)"
}
"`nArráncalas ya con:  Start-ScheduledTask -TaskName AltarDiario-Ciclo-plataforma ; Start-ScheduledTask -TaskName AltarDiario-Ciclo-producto ; Start-ScheduledTask -TaskName AltarDiario-Ciclo-auditor"
"Estado:  node scripts\ciclo-estado.mjs        Freno:  New-Item D:\Projects\AltarDiario\sesiones\STOP"
