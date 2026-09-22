$ErrorActionPreference = 'SilentlyContinue'

# Windows built-in library CLSIDs (whitelist, do not delete)
$whitelist = @(
  '{088e3905-0323-4b02-9826-5d99428e115f}',
  '{1cf1260c-4dd0-4ebb-811f-33c572699fde}',
  '{24ad3ad4-a569-4530-98e1-ab02f9417aa8}',
  '{374de290-123f-4565-9164-39c4925e467b}',
  '{3add1653-eb32-4cb0-bbd7-dfa0abb5acca}',
  '{3dfdf296-dbec-4fb4-81d1-6a3438bcf4de}',
  '{a0953c92-50dc-43bf-be83-3742fed03c9c}',
  '{a8cdff1c-4878-43be-b5fd-f8091c1c60d0}',
  '{b4bfcc3a-db2c-424c-b029-7fe99a87c641}',
  '{d3162b92-9365-467a-956b-92703aca08af}',
  '{f86fa3ab-70d2-4fc7-9c99-fcbf05467f3a}',
  'delegatefolders'
)

function Get-FriendlyName($clsid) {
  $n = (Get-ItemProperty "HKCU:\SOFTWARE\Classes\CLSID\$clsid" -ErrorAction SilentlyContinue).'(default)'
  if (-not $n) { $n = (Get-ItemProperty "HKLM:\SOFTWARE\Classes\CLSID\$clsid" -ErrorAction SilentlyContinue).'(default)' }
  if (-not $n) { $n = (Get-ItemProperty "HKLM:\SOFTWARE\Classes\WOW6432Node\CLSID\$clsid" -ErrorAction SilentlyContinue).'(default)' }
  return $n
}

$items = @()

# 1) MyComputer\NameSpace (this PC node)
foreach ($base in @(
  @{ Path='HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\MyComputer\NameSpace'; Loc='this-pc'; Hive='HKCU' },
  @{ Path='HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\MyComputer\NameSpace'; Loc='this-pc'; Hive='HKLM' }
)) {
  Get-ChildItem $base.Path -ErrorAction SilentlyContinue | ForEach-Object {
    $clsid = $_.PSChildName
    $friendly = Get-FriendlyName $clsid
    if (-not $friendly) { $friendly = '(no name)' }
    $isSys = $whitelist -contains $clsid.ToLower()
    $items += [PSCustomObject]@{ Key=$_.PSPath; Name=$friendly; Loc=$base.Loc; Hive=$base.Hive; IsSystem=$isSys }
  }
}

# 2) Desktop\NameSpace (nav bar root)
Get-ChildItem "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace" -ErrorAction SilentlyContinue | ForEach-Object {
  $clsid = $_.PSChildName
  $friendly = Get-FriendlyName $clsid
  if (-not $friendly) { $friendly = '(no name)' }
  $isSys = $whitelist -contains $clsid.ToLower()
  $items += [PSCustomObject]@{ Key=$_.PSPath; Name=$friendly; Loc='nav-root'; Hive='HKCU'; IsSystem=$isSys }
}

# 3) FTP accounts (network locations)
Get-ChildItem "HKCU:\Software\Microsoft\FTP\Accounts" -ErrorAction SilentlyContinue | ForEach-Object {
  $name = $_.PSChildName
  $items += [PSCustomObject]@{ Key=$_.PSPath; Name="FTP: $name"; Loc='ftp'; Hive='HKCU'; IsSystem=$false }
}

$thirdParty = @($items | Where-Object { -not $_.IsSystem })
$system = @($items | Where-Object { $_.IsSystem })

Write-Host ''
Write-Host '===== scan explorer sidebar icons =====' -ForegroundColor Cyan

Write-Host ''
Write-Host '--- system built-in (kept) ---' -ForegroundColor DarkGray
$system | ForEach-Object { Write-Host ('  [system] {0}' -f $_.Name) }

Write-Host ''
Write-Host '--- third-party icons to clean ---' -ForegroundColor Yellow
if ($thirdParty.Count -eq 0) {
  Write-Host '  none, clean.' -ForegroundColor Green
} else {
  $i = 0
  foreach ($t in $thirdParty) {
    $i++
    Write-Host ('  [{0}] {1}  ({2}/{3})' -f $i, $t.Name, $t.Hive, $t.Loc)
  }
}

Write-Host ''
Write-Host 'input number(s) to delete (e.g. 1,3), a = all, Enter = exit'
$ans = Read-Host 'select'

if ([string]::IsNullOrWhiteSpace($ans)) { exit }

$toDelete = @()
if ($ans.Trim().ToLower() -eq 'a') {
  $toDelete = $thirdParty
} else {
  $idxs = $ans.Split(',') | ForEach-Object { [int]($_.Trim()) } | Where-Object { $_ -ge 1 -and $_ -le $thirdParty.Count }
  foreach ($x in $idxs) { $toDelete += $thirdParty[$x-1] }
}

foreach ($d in $toDelete) {
  try {
    Remove-Item $d.Key -Recurse -Force -ErrorAction Stop
    Write-Host ('  deleted: {0}' -f $d.Name) -ForegroundColor Green
  } catch {
    Write-Host ('  failed: {0} ({1})' -f $d.Name, $_.Exception.Message) -ForegroundColor Red
  }
}

Write-Host ''
Write-Host 'restarting explorer...'
Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
if (-not (Get-Process -Name explorer -ErrorAction SilentlyContinue)) { Start-Process explorer }
Write-Host 'done. press Enter to exit.'
Read-Host
