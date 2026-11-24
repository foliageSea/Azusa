<h1 align="center">文件服务器</h1>

<p align="center">
  <a href="../README.md">Azusa</a> · <strong>WebDAV / SMB 2/3</strong>
</p>

## 添加与切换连接

在「设置 → 文件服务器」新增连接，可先测试再保存。读操作需要浏览权限；整理、搜刮或清理还需要相应的写入、移动或删除权限。

| 协议 | 填写说明 |
| --- | --- |
| WebDAV | 填写指向待管理目录的完整地址，例如 `https://nas.example.com/dav/`，以及服务要求的用户名和密码。实际使用建议使用 HTTPS。 |
| SMB | 主机填 DNS 名称或 IPv4，不填 `smb://`、端口或路径；共享名只填一级，例如 `Media`。填写用户名、密码及可选的域或工作组。连接根目录就是共享根；若只需开放子目录，请在 NAS 上另建共享。 |

保存不会自动切换。回到文件管理页选择连接，应用会从新连接的根目录开始浏览。有未执行的整理预览时需先确认放弃；文件操作或 AI 分析期间不能修改或切换连接。删除当前连接后不会自动选择其他服务；重启时会尝试恢复最后选择的连接。旧版单 WebDAV 配置会自动迁移，原有收藏继续按服务地址和用户名隔离。

## HTTP 代理

代理模式和地址全局共享，支持直连、系统代理和手动代理。手动地址格式为 `http://主机:端口`，仅支持无认证 HTTP 代理。选用系统或手动代理后，AI、TMDB 分别使用各自的代理开关（默认开启），每个 WebDAV 在连接编辑窗口单独设置（默认关闭）；关闭的服务始终直连。**SMB 不使用 HTTP 代理。**

- **系统解析**：Android 使用系统 `ProxySelector`，iOS/macOS 使用 CFNetwork，Windows 读取当前用户的系统网络代理，Linux 使用 GLib/GIO。按请求目标解析，保留系统绕过规则。
- **桌面环境变量**：Linux、macOS、Windows 优先使用请求协议对应的 `http_proxy` / `HTTP_PROXY` 或 `https_proxy` / `HTTPS_PROXY`，并遵守 `no_proxy` / `NO_PROXY`。桌面启动器不一定继承终端变量。
- **自动代理**：Android、iOS、macOS、Windows 不支持 PAC/WPAD；Linux 取决于 GIO 模块。遇到不支持的代理类型或读取失败会报错，不自动退回直连；系统明确返回不使用代理时才直连。
- **旧配置**：原来有代理地址则继续使用手动代理，否则继续直连。切换模式不会清除手动地址。

## SMB 使用范围
- 使用 TCP 445 直连及 NTLM 账号认证，要求消息签名。不支持 SMB1、来宾、Kerberos、自动发现、共享枚举、HTTP 代理、IPv6 或自定义端口。Azusa 不要求 SMB3 加密；不要把 SMB 暴露到公网，请使用可信局域网或 VPN。
- 不覆盖同名目标，不支持只改变大小写的重命名；删除目录只执行非递归删除。网络中断后请刷新确认结果再继续；服务端可能保留未完成的 `.azusa-stage-*` 暂存目录。写入需要目标目录允许创建文件和暂存子目录。
- Azusa 不访问服务端标识的符号链接或重解析点；应用不能识别被 NAS 当作普通目录返回的链接。请确保共享端禁止跟随可能跳出共享的链接，并使用最小权限的账号。客户端只能看到服务器为该账号列出的条目；目录非空时仍由服务器拒绝删除。SMB 整理仍会核对大小与修改时间，但没有与重命名原子绑定的版本条件。
- 未含 SMB 的配置仍导出为备份 v1，包含 SMB 时导出为 v2；当前版本都可以导入。密码不写入 SQLite，只有选择包含凭据并设置备份口令时才写入加密备份。

## 构建和联调

- [dart_smb2 0.4.1](https://pub.dev/packages/dart_smb2/versions/0.4.1) 的构建钩子从 GitHub 下载并校验固定 SHA-256 的 [libsmb2-r13](https://github.com/ales-drnz/dart_smb2/releases/tag/libsmb2-r13) 原生库。离线构建可按上游文档配置本地兼容库。原生资产要求 Android API 24+，Linux glibc 2.31+；不支持 Web。
- 发布包包含 [SMB 第三方许可与对应源代码](../assets/licenses/smb/SOURCE)。若升级依赖，请一并更新许可、对应源码版本和发布包内原生库校验。
- 运行 `sh tool/smb-integration/test.sh` 可对本机可抛弃的 Samba 共享运行 SMB 2.1 和 SMB 3.1.1 集成测试；常规 Flutter 测试不需要 Samba。

## 新增其他协议

文件管理、AI 整理、元数据搜刮和目录清理使用 [FileServerClient](../lib/features/organizer/file_server/file_server.dart)，不直接处理协议请求。

1. 实现 [FileServerConnection](../lib/features/organizer/file_server/file_server_connection.dart)，定义稳定的协议 ID 和独立配置模型。
2. 实现 `FileServerClient`，并在[协议工厂](../lib/features/organizer/file_server/file_server_factory.dart)注册。适配器执行离线校验，提供根目录和不含密码的收藏作用域，将原生路径转为逐段百分号编码的绝对路径，目录以 `/` 结尾。
3. 补充连接表单、持久化、凭据和备份。现有 WebDAV ID、凭据引用和收藏键不需要迁移。

适配器必须拒绝覆盖写入及根目录外的路径；无法确认完整目录内容时，`listAll` 必须失败而不是返回空目录。
