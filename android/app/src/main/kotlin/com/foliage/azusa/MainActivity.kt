package com.foliage.azusa

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.net.ConnectivityManager
import java.net.InetSocketAddress
import java.net.Proxy
import java.net.ProxySelector
import java.net.URI

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "azusa/system_proxy")
            .setMethodCallHandler { call, result ->
                if (call.method != "resolve") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                try {
                    val connectivity = getSystemService(CONNECTIVITY_SERVICE) as ConnectivityManager
                    val pac = connectivity.defaultProxy?.pacFileUrl
                    if (pac != null && pac.toString().isNotEmpty()) {
                        result.error("unsupported_proxy", "暂不支持 Android PAC 自动代理，请使用固定 HTTP 代理", null)
                        return@setMethodCallHandler
                    }
                    val uri = URI(call.arguments as String)
                    val proxies = ProxySelector.getDefault()?.select(uri) ?: listOf(Proxy.NO_PROXY)
                    val routes = proxies.map { proxy ->
                        when (proxy.type()) {
                            Proxy.Type.DIRECT -> "direct://"
                            Proxy.Type.HTTP -> {
                                val address = proxy.address() as InetSocketAddress
                                URI("http", null, address.hostString, address.port, null, null, null).toString()
                            }
                            else -> throw IllegalStateException("系统代理使用了不支持的 SOCKS 类型")
                        }
                    }
                    result.success(routes)
                } catch (error: Exception) {
                    result.error("proxy_error", error.message ?: "读取系统代理失败", null)
                }
            }
    }
}
