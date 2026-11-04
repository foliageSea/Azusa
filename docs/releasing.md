# 构建与发版

## 产物

发布 GitHub Release 后，`.github/workflows/release.yml` 自动校验版本、运行测试，并构建：

| 平台 | 架构 | 文件名 |
| --- | --- | --- |
| Android | arm64-v8a | `Azusa-<版本>-android-arm64-v8a.apk` |
| Windows | x64 | `Azusa-<版本>-windows-x64-setup.exe` |
| macOS | Apple Silicon / arm64 | `Azusa-<版本>-macos-arm64.dmg` |
| Linux | amd64 | `Azusa-<版本>-linux-amd64.deb` |

Android 使用正式密钥签名。Windows 不做代码签名；macOS 仅 ad-hoc 签名，不做 Developer ID 签名或公证，首次运行可能被 SmartScreen/Gatekeeper 提示或阻止。macOS 安装时将应用拖到 Applications，若被拦截，确认来源后按系统「隐私与安全性」中的提示允许打开。

Linux 在 Ubuntu 22.04 构建，DEB 从实际 ELF 文件推导系统库依赖；不承诺兼容所有 Debian/Ubuntu 版本。系统需要可用的 Secret Service（例如 GNOME Keyring）以保存凭据。桌面构建禁用仅由 Android 插件间接引入的 JNI，避免链接构建机 JDK；用户无需安装 Java。

所有构建成功后才开始将四个安装包和 `SHA256SUMS.txt` 上传到当前 Release。Release 本身会先发布，构建期间尚无安装包。上传不是原子操作，网络失败时可能只上传部分文件，需重跑上传 job。

## 首次配置 Android 签名

**已有正式签名应用时必须复用原密钥，不要重新生成**。不同密钥签名的 APK 不能覆盖安装，卸载重装会丢失本地数据。妥善离线备份 keystore、alias 和密码；GitHub Secrets 无法作为可取回的备份。

首次发布、尚无正式密钥时，可在已安装 JDK 的机器运行：

```bash
python3 tool/generate_android_signing.py ~/.local/share/azusa/release-signing
```

脚本拒绝向仓库内写入、拒绝覆盖已有目录，生成 RSA 4096 位 JKS 和四个 Secrets 值文件。密码不会打印到终端。目录权限为 `700`，文件为 `600`（Windows 还应自行限制 ACL）。

打开仓库 **Settings → Secrets and variables → Actions → New repository secret**，分别将以下文件的完整内容复制为同名 Secret（名称不包含 `.txt`）：

| 文件 / Secret | 内容 |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64.txt` | JKS 的单行 Base64，复制内容而非文件路径 |
| `ANDROID_KEYSTORE_PASSWORD.txt` | keystore 密码 |
| `ANDROID_KEY_ALIAS.txt` | 签名 alias |
| `ANDROID_KEY_PASSWORD.txt` | 私钥密码 |

密钥只在 Android job 临时还原，不上传为构建产物，结束后清理。缺少任何配置或签名不正确时，构建明确失败，不使用 debug 签名。

本地 release 构建可使用已被忽略的 `android/key.properties`：

```properties
storeFile=/absolute/path/to/azusa-release.jks
storePassword=<keystore password>
keyAlias=azusa-release
keyPassword=<key password>
```

Windows 的 `storeFile` 使用正斜杠或转义后的反斜杠。也支持 `ANDROID_KEYSTORE_PATH`、`ANDROID_KEYSTORE_PASSWORD`、`ANDROID_KEY_ALIAS`、`ANDROID_KEY_PASSWORD` 环境变量，优先于 properties 文件。

本地生成与 CI 相同的 arm64 安装包：

```bash
fvm flutter build apk --release --target-platform android-arm64 --split-per-abi \
  --android-project-arg=force-version-code-ignoring-abi=true
```

输出为 `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`。ABI 分包同时过滤第三方依赖的其他架构原生库；额外的 Gradle 参数确保 Android versionCode 仍为 `pubspec.yaml` 中的 build number，不叠加 ABI 编码。

## 一键发版

需要 Python 3.10+、Git、已通过 `gh auth login` 登录且具有仓库写权限的 GitHub CLI，以及 `.fvmrc` 指定的 Flutter（优先使用 FVM）。仓库必须允许 Actions 运行并写入 Release。首次使用前先将工作流与工具提交、推送到 GitHub。

工作区必须干净，当前分支跟踪 `origin` 的同名分支，且 HEAD 与远端一致。

```bash
# 仅校验并预览，不修改文件、提交或推送；需要联网及 gh 登录
python3 tool/release.py 1.0.1 --dry-run

# 修改版本、检查测试、提交、创建 Tag、推送并发布 Release
python3 tool/release.py 1.0.1
```

版本必须为递增的稳定版本 `X.Y.Z`。检查和测试通过后，脚本将 `pubspec.yaml` 更新为 `1.0.1+2`（build number 自动加一），同步 `snap/snapcraft.yaml`，提交版本文件、创建带注释的 `v1.0.1` Tag，并原子推送分支与 Tag，最后通过 `gh release create --verify-tag --generate-notes` 发布 Release。

`pubspec.yaml` 是唯一应用版本来源；Android、Windows、macOS 的应用版本与安装包版本均从它生成。为兼容 Windows 四段数字版本，各段和 build number 不超过 65535。不使用 Actions run number，以免重跑改变应用版本。

手动在 GitHub 发布 Release 也能触发，但 Tag 必须为 `vX.Y.Z`，对应提交的 `pubspec.yaml` 必须已包含匹配版本。仅推送 Tag 或保存 Release 草稿不会触发构建。不使用工作流的 `GITHUB_TOKEN` 创建 Release，以免其事件无法触发后续工作流。

## 失败恢复

脚本不会自动删除 Tag、重置提交或撤销远端修改。错误时先检查 `git status`、`git log -1`、本地和远端 Tag、GitHub Release 状态。

- **检查或测试失败**：修复问题、提交并推送，再重新发版。
- **版本提交或建 Tag 失败**：检查已经生成的版本文件和提交，手动完成剩余操作；不要直接重跑以免重复增加版本。
- **原子推送失败**：远端不会只收到分支或 Tag 中的一部分。核对状态并解决原因后，手动执行 `git push --atomic origin HEAD:refs/heads/<分支> refs/tags/v<版本>`。
- **推送成功但创建 Release 失败**：执行 `gh release create v<版本> --verify-tag --generate-notes --title 'Azusa <版本>'`，不要重新执行版本递增。
- **CI 构建失败**：修复 Secrets/外部依赖问题后，在 Actions 中 Re-run failed jobs；若需改源码，请创建新版本，不移动已发布 Tag。
- **仅修复工作流后重建旧版本**：将工作流修复提交到默认分支，再执行 `gh workflow run release.yml --ref main -f tag=v<版本>`。使用最新工作流，但应用源码、版本校验及打包脚本仍检出该 Tag 的提交；不会移动 Tag。不要对不可信分支运行带签名 Secrets 的工作流。
- **上传失败或需要补传**：在原始 workflow run 重跑上传 job（构建产物保留 7 天），超期则重跑所有 jobs。`--clobber` 会替换同名文件；替换前原文件会先删除，因此上传失败后需再次补传。

首次发版后应在真实 Android arm64、Windows x64、Apple Silicon macOS 和 Linux amd64 环境验证安装、启动、凭据保存及升级/卸载。CI 的签名/版本/包结构检查不能替代设备验证。
