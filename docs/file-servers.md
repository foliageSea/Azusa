# 文件服务器协议扩展

目前应用只提供 WebDAV。文件管理、AI 整理、刮削和目录清理依赖 [FileServerClient](../lib/features/organizer/file_server/file_server.dart)，不处理 WebDAV 请求或解析服务地址。

添加协议时：

1. 实现 [FileServerConnection](../lib/features/organizer/file_server/file_server_connection.dart)，定义稳定的协议 ID 和该协议自己的配置。
2. 实现 `FileServerClient`，在 [协议工厂](../lib/features/organizer/file_server/file_server_factory.dart) 注册新的 `FileServerProtocol`。由适配器进行离线校验，提供根目录和不含凭据的收藏作用域，并将原生路径转换成接口约定的绝对路径（逐段百分号编码，目录以 `/` 结尾）。
3. 补充该协议的连接表单、持久化、凭据和备份支持。现有 SQLite 连接表和备份 v1 仍专用于 WebDAV；既有连接 ID、安全存储引用以及收藏键无需迁移。

适配器必须拒绝写入覆盖、拒绝连接根目录外的路径，并在无法确认完整目录内容时让 `listAll` 失败，不得把错误当成空目录。参见 [假协议测试](../test/file_server_factory_test.dart) 的注册方式。
