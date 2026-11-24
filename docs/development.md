<h1 align="center">开发与测试</h1>

<p align="center">
  <a href="../README.md">Azusa</a> · <strong>开发指南</strong>
</p>

## 环境要求

- Flutter `>=3.47.0`，仓库通过 [FVM 配置](../.fvmrc) 固定为 `3.47.6`；Dart `>=3.13.0 <4.0.0`。版本约束以 [pubspec.yaml](../pubspec.yaml) 为准。
- 桌面开发需安装对应平台的原生构建工具，见 [Flutter 桌面开发文档](https://docs.flutter.dev/platform-integration/desktop)。
- 仓库包含 Android、iOS、Linux、macOS 和 Windows 平台工程；依赖 `dart:io`、原生 SQLite 等能力，不支持 Web。正式产物和架构见[构建与发版](releasing.md)，各原生平台仍需单独验证。

## 本地启动

在项目根目录执行（使用 FVM 时，将下列命令中的 `flutter` 换为 `fvm flutter`）：

```bash
flutter --version
flutter doctor -v
flutter pub get --enforce-lockfile
flutter gen-l10n
flutter devices
flutter run -d linux
```

在 Windows 或 macOS 桌面开发时，将最后一行的设备改为 `windows` 或 `macos`。启动后的设置参见[配置与使用](usage.md)。

## 测试与联调

### 常规检查

```bash
flutter analyze
flutter test
python3 -m unittest discover -s tool -p 'test_*.py'
```

Python 工具测试不需要安装 WebDAV 依赖。Flutter 测试覆盖重命名计划与执行、网络服务、本地数据库、执行历史、AI 用量、目录收藏、启动连接及界面行为等。需要真实服务的测试在缺少相应环境变量时会跳过。

### 本地 SMB 联调

需要 Docker，且本机 `127.0.0.1:445` 可用。脚本依次启动启用强制签名的 SMB 2.1 和 SMB 3.1.1 测试共享，验证分页枚举、权限、流式传输、不覆盖写入及整理、搜刮、清理流程。容器仅对本机开放，结束后自动移除。

```bash
sh tool/smb-integration/test.sh
```

更多限制与构建说明见[文件服务器文档](file-servers.md)。

### 本地 WebDAV 联调

项目提供仅监听 `127.0.0.1` 的 Python WebDAV 测试服务，自动生成中文路径、剧集文件占位数据和字幕，并记录请求日志。

以下命令适用于 Linux/macOS；服务脚本要求 `/tmp/opencode` 目录存在且可写：

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -r tool/webdav-requirements.txt
mkdir -p /tmp/opencode
python tool/local_webdav.py
```

测试数据与样例验证见[本地 WebDAV 测试数据](../tool/README.md)。默认连接信息：

| 字段 | 值 |
| --- | --- |
| 地址 | `http://127.0.0.1:18765/dav/` |
| 用户名 | `azu` |
| 密码 | `azu-local-test` |

使用 `--port` 可指定其他端口。启动时会输出 `workspace` 和 `request_log` 路径；测试文件均为占位数据，不是真实视频。

保持服务运行，在另一个终端执行：

```bash
AZU_WEBDAV_URL=http://127.0.0.1:18765/dav/ \
  flutter test test/local_webdav_test.dart
```

如需恢复初始测试文件，将下方示例替换为启动时输出的实际 `workspace` 路径：

```bash
python tool/reset_webdav.py /tmp/opencode/azu-webdav-xxxxxxxx
```

该操作会要求确认，并删除指定测试工作区 `share/` 下的全部内容后重新创建样例。脚本仅允许重置经校验的 `/tmp/opencode/azu-webdav-*` 工作区。

### 真实 AI + TMDB 联调

保持本地 WebDAV 服务运行，使用自己的 AI 与 TMDB 凭据执行：

```bash
export AZU_WEBDAV_URL='http://127.0.0.1:18765/dav/'
export AZU_AI_URL='https://api.openai.com/v1'
export AZU_AI_MODEL='your-tool-capable-model'
export AZU_AI_KEY='your-ai-api-key'
export AZU_TMDB_KEY='your-tmdb-api-key-or-read-access-token'

flutter test test/live_ai_webdav_test.dart
```

此测试会调用真实外部服务，可能产生费用，并在 WebDAV 上创建测试目录、上传占位文件和执行重命名。测试中的 WebDAV 用户名与密码固定为上述本地测试凭据，请勿指向生产目录，也不要将真实密钥提交到仓库。

## 桌面发布构建

在相应操作系统及其已配置的工具链上，选择对应命令执行：

```bash
flutter build linux --release
flutter build windows --release
flutter build macos --release
```

这些命令只构建桌面应用，不会生成 GitHub Release 安装包。发布安装包时，按[构建与发版](releasing.md)操作。

## 目录导览

| 目录 | 职责 |
| --- | --- |
| [lib/app](../lib/app) | 应用外壳、路由、主题和窗口外观 |
| [lib/core](../lib/core) | 数据库、设置、日志和桌面窗口能力 |
| [lib/features/assistant](../lib/features/assistant) | 整理对话、目录选择和方案预览 |
| [lib/features/organizer](../lib/features/organizer) | 通用文件服务器接口、WebDAV/SMB、AI/TMDB、搜刮、整理和历史 |
| [lib/features/settings](../lib/features/settings) | 设置页面组件、配置备份和诊断组件 |
| [lib/l10n](../lib/l10n) / [lib/shared](../lib/shared) | 中英文本地化和共享组件 |
| [test](../test) / [tool](../tool) | 应用测试、联调、打包和发版工具 |
| [assets](../assets) | 字体、图标和第三方许可 |

主要技术包括 Flutter/Dart、Forui、Riverpod、GoRouter、Dio、LangChain 和 SQLite。依赖版本以 [pubspec.yaml](../pubspec.yaml) 与 [pubspec.lock](../pubspec.lock) 为准。

## 应用图标

通过 `icons_launcher` 管理各平台配置，由 SVG 按目标尺寸直接渲染圆角版 az 标识。生成步骤见[图标工具说明](../tool/icons/README.md)。

```bash
npm ci --prefix tool/icons
npm run generate --prefix tool/icons
```
