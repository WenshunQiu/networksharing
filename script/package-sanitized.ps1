param(
    [string]$Source = (Split-Path -Parent $PSScriptRoot),
    [string]$Output = (Join-Path (Split-Path -Parent $PSScriptRoot) "dist/networksharing-source-sanitized.zip")
)

$ErrorActionPreference = "Stop"
$sourcePath = (Resolve-Path -LiteralPath $Source).Path
$outputPath = [System.IO.Path]::GetFullPath($Output)
$outputParent = Split-Path -Parent $outputPath
if (-not (Test-Path -LiteralPath $outputParent)) {
    New-Item -ItemType Directory -Path $outputParent -Force | Out-Null
}

$stage = Join-Path ([System.IO.Path]::GetTempPath()) ("networksharing-package-" + [guid]::NewGuid().ToString("N"))
$null = New-Item -ItemType Directory -Path $stage
$excludedDirectories = @(
    ".git", ".dart_tool", ".fvm", ".idea", ".vscode", ".widget_preview", ".gradle",
    "build", "dist", "documents", "logs", "coverage", "node_modules",
    "ephemeral", "DerivedData", "Pods", "target", "__pycache__"
)
$excludedFiles = @(
    ".flutter-plugins-dependencies", "devtools_options.yaml", "local.properties",
    "Generated.xcconfig", "flutter_export_environment.sh", ".last_build_id",
    "pwsh-history", "windows-build.log", "*.log", "*.iml", "*.jks",
    "*.keystore", "*.p12", "*.pem", "*.key", ".env", ".env.*",
    "*.apk", "*.aab", "*.exe", "*.dll", "*.so", "*.dylib", "*.class",
    "*.pyc", "*.bak", "*.tmp", "*.swp"
)
$tokenPatterns = @(
    '(?im)(github[_-]?token|api[_-]?key|access[_-]?token)\s*([:=])\s*("[^"\r\n]+"|''[^''\r\n]+'')',
    '(?i)\bgh[pousr]_[A-Za-z0-9_]{20,}',
    '(?im)\bBearer\s+[A-Za-z0-9._-]{20,}',
    '(?i)[A-Z]:[\\/]+(?:Users|File)[^\s"'']+',
    '(?i)/home/[^/\s"'']+'
)

try {
    Get-ChildItem -LiteralPath $sourcePath -Recurse -File -Force | ForEach-Object {
        $relative = [System.IO.Path]::GetRelativePath($sourcePath, $_.FullName)
        $segments = $relative -split '[\\/]'
        if ($segments | Where-Object { $excludedDirectories -contains $_ }) { return }
        foreach ($pattern in $excludedFiles) {
            if ($_.Name -like $pattern) { return }
        }
        if ($_.Extension -in @(".png", ".jpg", ".jpeg", ".ico", ".gif", ".webp") -and $_.Length -gt 10MB) { return }

        $target = Join-Path $stage $relative
        $targetDirectory = Split-Path -Parent $target
        if (-not (Test-Path -LiteralPath $targetDirectory)) {
            New-Item -ItemType Directory -Path $targetDirectory -Force | Out-Null
        }
        Copy-Item -LiteralPath $_.FullName -Destination $target

        if ($_.Extension -in @(".md", ".yaml", ".yml", ".toml", ".json", ".xml", ".gradle", ".kts", ".ps1", ".dart", ".kt", ".rs", ".cpp", ".h", ".txt", ".properties", ".plist", ".swift", ".sh", ".bat", ".cmake", ".podspec", ".manifest")) {
            $content = [System.IO.File]::ReadAllText($target)
            foreach ($pattern in $tokenPatterns) {
                $content = [regex]::Replace($content, $pattern, "[REDACTED]")
            }
            [System.IO.File]::WriteAllText($target, $content, [System.Text.UTF8Encoding]::new($false))
        }
    }

    # Replace contributor workflow and local paths with a user-facing project README.
    @'
# NetworkSharing

NetworkSharing 是一款面向 Android 手机/平板和 Windows 电脑的跨平台应用。它通过低功耗蓝牙（BLE）配对设备、检测互联网连接状态，并在一端断网时协调另一端提供热点。

应用使用 Flutter 和 Fluent UI 构建，可适配手机窄屏与桌面宽屏。项目集成 Rust 和 flutter_rust_bridge；平台网络操作由 Android 与 Windows 对应实现负责。

## 功能概览

 - Android 可搜索 Windows 电脑并通过 BLE 连接，再输入电脑显示的配对码完成应用配对。
- 保存配对设备信息，并在应用启动时尝试恢复连接。
- 通过 HTTPS 检查百度和 Google 的可达性，任一站点可达即视为联网。
- 本机无法联网时，可请求已配对设备提供热点。热点提供方可对该设备选择每次询问、自动允许或自动拒绝。
- 获得允许后，尝试开启或复用对端热点，通过已配对的 BLE 连接传递 Wi-Fi 信息，并让请求方尝试连接。
- 展示连接与共享状态，支持本地通知、Android 后台通知操作、Windows 系统托盘和诊断工具。

当前版本支持一台已配对设备和一个活动共享会话。文件传输、剪贴板同步、远程摄像头/麦克风和手机投屏不属于当前功能。

## 环境要求

- 安装与 pubspec.yaml 中 SDK 约束兼容的 Flutter stable 和 Dart，并使用 FVM 管理 Flutter。
- 安装 Rust stable，以及目标平台构建所需的 Rust 工具链和编译目标。
- 构建 Android 版本需要 Android Studio、Android SDK 和 NDK；构建 Windows 版本需要 Visual Studio C++ 桌面开发组件和 Windows SDK。
- 蓝牙和热点功能需要兼容的蓝牙、Wi-Fi 设备。验证 Android 后台与热点流程需要 Android 实机。

项目使用的具体版本可查看 .fvmrc、pubspec.yaml 和依赖锁定文件。

## 构建与运行

在项目根目录执行以下命令以获取依赖、分析代码并运行测试：

~~~powershell
fvm flutter pub get
fvm flutter analyze
fvm flutter test
~~~

构建 Android Debug APK 或 Windows 桌面应用：

~~~powershell
fvm flutter build apk --debug
fvm flutter build windows --debug
~~~

开发时运行 Windows 桌面应用：

~~~powershell
fvm flutter run -d windows
~~~

Android APK 输出到 build/app/outputs/flutter-apk/；Windows 可执行文件输出到 build/windows/。

## 配对与使用

1. 在两台设备上安装并打开 NetworkSharing，按系统提示授予蓝牙、附近设备和通知权限。
2. 保持 Windows 应用运行，配对页面会显示当前应用配对码。
3. 在 Android 上搜索 Windows 电脑并连接，然后输入电脑显示的配对码完成应用配对。
4. 确认两端都显示设备已配对且在线。应用重启后会尝试恢复已保存的连接。
5. 一端无法联网时，可通过通知或共享页面请求对端热点。提供方保存的设备权限决定该请求需要询问、自动允许还是自动拒绝。
6. 按需确认 Android 系统显示的 Wi-Fi 操作提示，并在设备状态页查看最终连接结果。

如果 Android 厂商限制后台运行，请在系统的后台运行或电池管理设置中允许 NetworkSharing。Windows 关闭主窗口后应用会留在系统托盘；选择托盘菜单中的退出命令可完全关闭应用。

## 平台说明

- Android 热点控制和配置读取受系统版本、厂商实现及设备权限影响。应用可尝试 Root 方式，但普通应用仍可能被系统拒绝。
- Android 连接 Wi-Fi 时可能要求系统确认。后台允许对端开启热点与请求本机加入 Wi-Fi 是两个独立的系统操作。
- Windows 热点能力受 Windows 网络 API、无线网卡、驱动和系统策略影响。
- Android 后台服务可能受到电池管理限制；用户强制停止应用后，连接恢复不会正常运行。
- 某些 Android 设备无法提供热点客户端数量。无法读取数量时，应用不会将其当作零并据此自动关闭热点。
- 当前 BLE 由 Flutter BLE 插件处理，尚未完成迁移至 Rust/btleplug。

## 诊断

应用内诊断页面可检查网络，并测试通知、热点和 Wi-Fi 操作。可通过应用的日志诊断入口查看或导出 JSON Lines 日志。分享日志前请检查其中是否含有不宜公开的信息；不要附上热点密码、配对码或连接恢复令牌。

项目采用 MVVM 结构：页面负责展示状态和收集操作，ViewModel 协调应用行为，Repository/Provider 封装持久化、蓝牙、通知和平台网络能力。
'@ | Set-Content -LiteralPath (Join-Path $stage "README.md") -Encoding utf8

    if (Test-Path -LiteralPath $outputPath) { Remove-Item -LiteralPath $outputPath -Force }
    Compress-Archive -Path (Join-Path $stage "*") -DestinationPath $outputPath -CompressionLevel Optimal
    Write-Output "Created sanitized source archive: $outputPath"
} finally {
    Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
}
