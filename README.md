# Azusa

Azusa 是一个使用 Flutter 构建的 WebDAV 剧集整理工具。连接 NAS 或其他 WebDAV 服务后，可浏览远程文件，借助兼容 OpenAI 的 AI 服务与 TMDB 数据生成重命名建议，经人工预览、编辑和确认后再执行。

> AI 只生成建议，不直接修改文件。执行整理会真实修改远程文件名，请先在测试目录验证并备份重要数据。

## 功能

- **WebDAV 文件浏览**：浏览目录、筛选文件。
- **目录收藏**：按 WebDAV 服务与用户保存常用目录。
- **AI 剧集整理**：通过工具调用查询 TMDB 剧集、季和单集信息，生成带匹配依据的建议。
- **人工确认**：逐项修改目标文件名、排除不需要处理的文件，再执行选中项。
- **执行保护**：检查文件名、扩展名、重复目标、现有文件冲突和源文件属性；串行执行，失败即停止。
- **历史与用量**：本地保存执行历史和 AI 调用记录，展示 Token 用量及可用时的费用估算。
- **连接与代理**：分别配置 WebDAV、AI、TMDB，以及各服务是否使用 HTTP 代理。
- **明暗主题**：通过页面顶部按钮切换亮色与暗色模式。

## 环境要求

| 项目 | 要求 |
| --- | --- |
| Flutter | `>=3.47.0`，项目 `.fvmrc` 固定为 `3.47.6` |
| Dart | `>=3.13.0 <4.0.0` |
| 远程文件服务 | 可访问的 WebDAV 服务；写操作需要相应权限 |
| AI 服务 | 兼容 OpenAI Chat Completions，模型需支持工具调用 |
| 剧集元数据 | TMDB API Key 或 API Read Access Token |
| Python | 仅本地 WebDAV 联调需要，使用 Python 3 |

仓库包含 Linux、macOS、Windows、Android 和 iOS 平台工程。当前代码依赖 `dart:io`、原生 SQLite 等原生能力，**不支持 Web**；各原生平台仍需分别完成构建和设备验证。

## 快速开始

在项目根目录执行，确保当前 Flutter 版本符合上述要求：

```bash
flutter --version
flutter doctor -v
flutter pub get
flutter gen-l10n
flutter run -d linux
```

Windows 或 macOS 开发环境分别将最后一条命令替换为：

```bash
flutter run -d windows
flutter run -d macos
```

桌面开发需先安装对应平台的原生构建工具，参见 [Flutter 桌面开发文档](https://docs.flutter.dev/platform-integration/desktop)。

### 连接配置

启动应用后，进入「连接」页面填写并保存配置：

| 配置 | 说明 |
| --- | --- |
| WebDAV 地址 | 指向待管理目录的完整地址，例如 `https://nas.example.com/dav/` |
| 用户名与密码 | WebDAV 服务的访问凭据 |
| AI 地址 | OpenAI 兼容 API 的基础地址，默认 `https://api.openai.com/v1`，不是完整的 `/chat/completions` 地址 |
| AI 模型与 Key | 填写服务实际支持的模型名称及 API Key |
| TMDB 凭据 | 支持 API Key 或 API Read Access Token |
| HTTP 代理 | 支持直连、系统代理和手动代理；手动地址格式为 `http://主机:端口`，仅支持无认证 HTTP 代理 |

选择系统代理或手动代理后，可分别选择 AI、TMDB、WebDAV 是否使用该代理；默认 AI、TMDB 启用，WebDAV 关闭。关闭某服务的代理开关后，该服务始终直连。

- **系统代理**：Android 使用系统 `ProxySelector`，iOS/macOS 使用 CFNetwork，Windows 读取当前用户的系统网络代理，Linux 使用 GLib/GIO 的代理解析器（可用的桌面配置取决于系统安装的 GIO 模块）。按请求目标解析，保留系统绕过规则。
- **桌面环境变量**：Linux、macOS、Windows 优先使用请求协议对应的 `http_proxy`/`HTTP_PROXY` 或 `https_proxy`/`HTTPS_PROXY`，并遵守 `no_proxy`/`NO_PROXY`。桌面启动器启动的应用不一定继承终端环境变量。
- **限制**：仅支持固定、无认证的 HTTP 代理；Android、iOS、macOS、Windows 的 PAC/WPAD 自动代理暂不支持，检测到时会报错；Linux 自动代理是否可解析取决于 GIO 模块。不支持的代理类型或读取失败不会自动回退直连；系统明确返回不使用代理时则直连。
- **配置兼容**：旧配置有代理地址时继续使用手动代理，没有地址时继续直连；切换模式不会清除已有手动代理地址。

日常使用的连接信息在应用内配置，不需要创建 `.env` 文件。下文的 `AZU_*` 环境变量仅用于测试。

### 整理流程

1. 连接 WebDAV，打开需要整理的剧集目录。
2. 进入 AI 助手，可补充剧名、季数、命名偏好等要求。
3. 确认将目录路径和文件名发送给配置的 AI 服务。
4. 等待 AI 查询 TMDB 并生成建议，逐项核对匹配依据与目标文件名。
5. 编辑名称或排除不需要处理的文件，确认后执行重命名。
6. 查看执行结果和历史；如中途失败，先刷新远程目录核对实际状态。

默认建议格式为：

```text
剧名 - S01E01 - 单集名称.mkv
```

AI 的默认命名要求包括保留原扩展名、保留字幕语言标记，特殊集使用 `S00`。实际建议仍需人工检查。

## 安全与限制

- AI 分析会发送所选目录路径、文件名及补充要求，**不会上传文件内容**；请确认这些信息可以交给你配置的服务处理。
- WebDAV 密码、AI Key 和 TMDB 凭据通过 `flutter_secure_storage` 保存；普通连接配置与外观设置保存在本地偏好中。
- 执行历史、AI 用量和目录收藏保存在应用支持目录下的 `azusa.sqlite3` 中。
- AI 整理只针对当前目录中的文件，不递归整理子目录；当前目录文件超过 500 个时需要选择更小的目录。
- 重命名建议不能改变所在目录。执行前会校验冲突，并在每项操作前重新检查源文件和目标文件。
- 批量操作不是事务：遇到失败立即停止，已经完成的修改不会自动回滚。
- HTTP 可用于本地联调，但不提供传输加密；实际服务建议使用 HTTPS。
- AI 用量与费用估算依赖服务返回的数据和可用价格信息，不应作为最终账单依据。

## 开发与测试

### 常规检查

```bash
flutter analyze
flutter test
```

测试覆盖重命名计划与执行、网络服务、本地数据库、执行历史、AI 用量、目录收藏、启动连接及界面行为等。需要真实服务的测试在缺少相应环境变量时会跳过。

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

默认连接信息：

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

重置脚本自身的测试无需安装 WebDAV 依赖：

```bash
python3 -m unittest discover -s tool -p 'test_*.py'
```

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

### 桌面发布构建

在相应操作系统及其已配置的工具链上，选择对应命令执行：

```bash
flutter build linux --release
flutter build windows --release
flutter build macos --release
```

## 应用图标

保留圆角版 az 标识，使用 `icons_launcher` 管理平台配置，再从 SVG 按目标尺寸直接渲染，避免位图反复缩放。生成步骤见 [图标工具说明](<tool/icons/README.md>)。

```bash
npm ci --prefix tool/icons
npm run generate --prefix tool/icons
```

## 项目结构

```text
lib/
├── main.dart                    # 启动、日志与设置初始化
├── app/                         # 应用入口、路由、主题与外壳
├── core/                        # 数据库、设置、日志与窗口能力
├── features/
│   ├── organizer/
│   │   ├── ai/                  # AI Agent、TMDB、用量与价格信息
│   │   ├── connections/         # 连接配置与 HTTP 客户端
│   │   ├── dav/                 # WebDAV、路径处理与目录收藏
│   │   ├── history/             # 执行历史
│   │   ├── organizer_state.dart # 整理状态与流程控制
│   │   └── rename_plan.dart     # 重命名计划校验与执行
│   └── settings/                # 尚未接入路由的完整外观设置与诊断界面
├── l10n/                        # 中英文 ARB 与生成的本地化代码
└── shared/                      # 共享组件与辅助方法
test/                            # Flutter/Dart 测试
tool/                            # 本地 WebDAV 服务、重置脚本及测试
assets/                          # 字体资源
```

主要技术包括 Flutter/Dart、Forui、Riverpod、GoRouter、Dio、LangChain 和 SQLite。依赖版本以 [`pubspec.yaml`](pubspec.yaml) 与 [`pubspec.lock`](pubspec.lock) 为准。

## 字体与许可

项目使用 MiSans 字体，© 小米科技有限责任公司，使用与分发需遵循《MiSans 字体知识产权许可协议》。第三方依赖遵循各自许可证。

项目代码采用 [MIT License](LICENSE) 开源。MiSans 字体及第三方依赖不适用本项目的 MIT 许可，仍遵循各自许可证；公开发布或再分发时，请核对并保留相应许可声明。
