import '../file_server/file_server.dart';
import '../file_server/file_server_connection.dart';
import '../file_server/file_server_paths.dart';

class SmbConnection implements FileServerConnection {
  const SmbConnection({
    required this.id,
    required this.name,
    required this.host,
    required this.share,
    this.domain = '',
    required this.username,
    this.password = '',
  });

  static const protocolId = 'smb';

  @override
  String get protocol => protocolId;
  @override
  final String id;
  @override
  final String name;

  final String host, share, domain, username, password;

  String get displayAddress =>
      'smb://${host.trim()}/${Uri.encodeComponent(share)}';

  void validate() {
    if (name.trim().isEmpty) throw const FormatException('请输入连接名称');
    final server = host.trim();
    if (server.length > 253 ||
        !_dns.hasMatch(server) ||
        (_numericHost.hasMatch(server) && !_validIpv4(server))) {
      throw const FormatException('SMB 主机必须为 DNS 名称或 IPv4 地址');
    }
    if (share.length > 80 ||
        !validFileName(share) ||
        share.trim() != share ||
        share.contains(RegExp(r'[\[\];=,+]'))) {
      throw const FormatException('SMB 共享名称无效');
    }
    if (username.trim().isEmpty ||
        _accountControl.hasMatch(username) ||
        _accountControl.hasMatch(domain) ||
        password.contains('\u0000')) {
      throw const FormatException('请输入有效的 SMB 用户名，域请单独填写');
    }
  }

  FileServerScope get scope {
    validate();
    final server = host.trim().toLowerCase().replaceFirst(RegExp(r'\.$'), '');
    return (
      endpoint: 'smb://$server/${Uri.encodeComponent(share.toLowerCase())}/',
      username:
          '${Uri.encodeComponent(domain.trim().toLowerCase())}/${Uri.encodeComponent(username.trim().toLowerCase())}',
      root: '/',
    );
  }

  static bool _validIpv4(String host) {
    final parts = host.split('.');
    return parts.length == 4 &&
        parts.every((part) {
          final number = int.tryParse(part);
          return number != null &&
              number >= 0 &&
              number <= 255 &&
              '$number' == part;
        });
  }

  static final _dns = RegExp(
    r'^[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*\.?$',
  );
  static final _numericHost = RegExp(r'^[0-9.]+$');
  static final _accountControl = RegExp(r'[/\\\x00-\x1F\x7F]');
}
