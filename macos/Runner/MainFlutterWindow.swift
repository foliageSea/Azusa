import Cocoa
import FlutterMacOS
import CFNetwork

class MainFlutterWindow: NSWindow {
  private let backdrop = NSVisualEffectView(frame: .zero)
  private var windowEffectsChannel: FlutterMethodChannel?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    flutterViewController.backgroundColor = .clear
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // Insert the effect beneath Flutter's rendering view without replacing its controller.
    let flutterContainer = flutterViewController.view
    backdrop.frame = flutterContainer.bounds
    backdrop.autoresizingMask = [.width, .height]
    backdrop.material = .sidebar
    backdrop.blendingMode = .behindWindow
    backdrop.state = .followsWindowActiveState
    flutterContainer.addSubview(backdrop, positioned: .below, relativeTo: nil)
    configureTransparentWindow()

    RegisterGeneratedPlugins(registry: flutterViewController)
    let effects = FlutterMethodChannel(
      name: "azusa/window_effects", binaryMessenger: flutterViewController.engine.binaryMessenger)
    windowEffectsChannel = effects
    effects.setMethodCallHandler { [weak self] call, result in
      guard call.method == "setBrightness" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let dark = call.arguments as? Bool else {
        result(FlutterError(
          code: "invalid_arguments", message: "setBrightness requires a boolean.", details: nil))
        return
      }
      // Reapply the configuration after window_manager has initialized the window.
      self?.configureTransparentWindow()
      self?.backdrop.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
      result(nil)
    }

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

  private func configureTransparentWindow() {
    isOpaque = false
    backgroundColor = .clear
    hasShadow = true
    (contentViewController as? FlutterViewController)?.backgroundColor = .clear
  }
}
