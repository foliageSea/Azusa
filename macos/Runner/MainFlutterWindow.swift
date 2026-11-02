import Cocoa
import FlutterMacOS
import CFNetwork

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    let channel = FlutterMethodChannel(
      name: "azusa/system_proxy", binaryMessenger: flutterViewController.engine.binaryMessenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "resolve" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let value = call.arguments as? String, let url = URL(string: value),
            let settings = CFNetworkCopySystemProxySettings()?.takeRetainedValue() else {
        result(FlutterError(code: "proxy_error", message: "读取系统代理失败", details: nil))
        return
      }
      let proxies = CFNetworkCopyProxiesForURL(url as CFURL, settings).takeRetainedValue() as NSArray
      var routes: [String] = []
      for case let proxy as NSDictionary in proxies {
        let type = proxy[kCFProxyTypeKey] as? String
        if type == kCFProxyTypeNone as String {
          routes.append("direct://")
        } else if (type == kCFProxyTypeHTTP as String || type == kCFProxyTypeHTTPS as String),
                  let host = proxy[kCFProxyHostNameKey] as? String,
                  let port = proxy[kCFProxyPortNumberKey] as? Int {
          var components = URLComponents()
          components.scheme = "http"
          components.host = host
          components.port = port
          guard let address = components.string else {
            result(FlutterError(code: "proxy_error", message: "系统代理地址无效", details: nil))
            return
          }
          routes.append(address)
        } else {
          result(FlutterError(code: "unsupported_proxy", message: "系统代理包含不支持的 PAC 或 SOCKS 类型，请使用固定 HTTP 代理", details: nil))
          return
        }
      }
      result(routes)
    }

    super.awakeFromNib()
  }
}
