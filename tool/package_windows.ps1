# 打包 Windows 发布版：构建 → 带版本号的目录 → zip。
#
# 产物名必须带 windows 与 .zip：客户端检查更新时按这个名字挑资产
# （见 lib/core/update/app_release.dart 的发布约定）。
#
# 用法：
#   powershell -ExecutionPolicy Bypass -File tool/package_windows.ps1
#   powershell -ExecutionPolicy Bypass -File tool/package_windows.ps1 -SkipBuild
#   powershell -ExecutionPolicy Bypass -File tool/package_windows.ps1 -Installer
#
# -Installer 需要本机安装 Inno Setup 6（ISCC.exe）；没有就只产 zip，不报错。
#
# 注意：项目路径含中文时，当前 Flutter/MSBuild 组合会在自定义生成步骤读错
# PROJECT_DIR（app.dill 乱码），本脚本需在纯 ASCII 路径下运行，CI 不受影响。
param(
  [switch]$SkipBuild,
  [switch]$Installer
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

# 版本号从 pubspec 读，避免产物名和 tag / 应用内版本对不上。
$match = Select-String -Path 'pubspec.yaml' -Pattern '^version:\s*([0-9]+\.[0-9]+\.[0-9]+)' |
  Select-Object -First 1
if (-not $match) { throw 'pubspec.yaml 里找不到 version' }
$version = $match.Matches[0].Groups[1].Value

if (-not $SkipBuild) {
  flutter build windows --release
  if ($LASTEXITCODE -ne 0) { throw "flutter build windows 失败：$LASTEXITCODE" }
}

$release = 'build\windows\x64\runner\Release'
if (-not (Test-Path $release)) { throw "找不到构建产物：$release" }

$name = "auto-chaoxing-$version-windows-x64"
$dist = Join-Path 'dist' $name
$zip = Join-Path 'dist' "$name.zip"

if (Test-Path $dist) { Remove-Item $dist -Recurse -Force }
New-Item -ItemType Directory -Path $dist -Force | Out-Null
Copy-Item -Path (Join-Path $release '*') -Destination $dist -Recurse -Force

if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path (Join-Path $dist '*') -DestinationPath $zip -CompressionLevel Optimal

$size = [math]::Round((Get-Item $zip).Length / 1MB, 1)
Write-Host "已生成 $zip ($size MB)"
Write-Host '发布时把这个 zip 传成 Release 资产，应用内「检查更新」就能挑到它。'

if ($Installer) {
  # Inno Setup 6 的安装位置不固定，先查 PATH 再查默认目录。
  $iscc = Get-Command ISCC.exe -ErrorAction SilentlyContinue
  if (-not $iscc) {
    $candidates = @(
      (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe'),
      (Join-Path $env:ProgramFiles 'Inno Setup 6\ISCC.exe')
    )
    $found = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($found) { $iscc = Get-Item $found }
  }
  if (-not $iscc) {
    Write-Warning '未找到 Inno Setup 6（ISCC.exe），跳过安装器；zip 仍可直接分发。'
  } else {
    & $iscc.Source "/DMyAppVersion=$version" 'tool\windows\installer.iss'
    if ($LASTEXITCODE -ne 0) { throw "Inno Setup 编译失败：$LASTEXITCODE" }
    Write-Host "已生成 dist\auto-chaoxing-setup-$version.exe"
  }
}
