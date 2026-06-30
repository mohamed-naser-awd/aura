param(
  [Parameter(Mandatory = $true)][string]$Endpoint,   # e.g. 192.168.50.64:34283  (TOP of Wireless debugging screen)
  [string]$PairPort = "",
  [string]$Code = "",
  [string]$DeviceHost = "192.168.50.64"
)

$adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
$apk = "C:\Users\dell\code\aura\build\app\outputs\flutter-apk\app-debug.apk"

if ($PairPort -and $Code) {
  & $adb pair ("{0}:{1}" -f $DeviceHost, $PairPort) $Code
}

$online = $false
for ($i = 0; $i -lt 10; $i++) {
  & $adb connect $Endpoint *> $null
  $list = (& $adb devices) -join "`n"
  if ($list -match ("{0}\s+device" -f [regex]::Escape($Endpoint))) { $online = $true; break }
  & $adb disconnect $Endpoint *> $null
  Start-Sleep -Milliseconds 700
}

if (-not $online) { Write-Output "NOT ONLINE:"; & $adb devices; exit 1 }

& $adb -s $Endpoint install -r $apk
& $adb -s $Endpoint shell monkey -p ca.aepg.aura -c android.intent.category.LAUNCHER 1 *> $null
Write-Output "DONE -> $Endpoint"
