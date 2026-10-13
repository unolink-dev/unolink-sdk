import Flutter
import Foundation

/// Flutter bridge to the Unolink iOS SDK (compiled into this pod, so `Unolink` is used directly).
public final class UnolinkFlutterPlugin: NSObject, FlutterPlugin {
    private let channel: FlutterMethodChannel

    init(channel: FlutterMethodChannel) {
        self.channel = channel
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "dev.unolink/sdk", binaryMessenger: registrar.messenger())
        registrar.addMethodCallDelegate(UnolinkFlutterPlugin(channel: channel), channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]
        switch call.method {
        case "configure":
            let level: LogLevel
            switch args["logLevel"] as? String {
            case "none": level = .none
            case "error": level = .error
            case "info": level = .info
            case "debug": level = .debug
            default: level = .warn
            }
            let baseUrl = (args["baseUrl"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? UnolinkOptions.defaultBaseURL
            Unolink.configure(apiKey: args["apiKey"] as? String ?? "",
                              options: UnolinkOptions(baseURL: baseUrl, logLevel: level, debug: args["debug"] as? Bool ?? false),
                              sdkName: "flutter", sdkVersion: args["sdkVersion"] as? String ?? "0")
            Unolink.onDeferredDeepLink { [weak self] link in
                self?.channel.invokeMethod("onDeferredDeepLink", arguments: [
                    "deepLink": link.deepLink as Any,
                    "params": link.params,
                    "linkSlug": link.linkSlug as Any,
                    "clickId": link.clickId,
                ])
            }
        case "track":
            Unolink.track(args["name"] as? String ?? "", properties: args["properties"] as? [String: Any])
        case "purchase":
            guard let amount = Decimal(string: args["amount"] as? String ?? "", locale: Locale(identifier: "en_US_POSIX")) else {
                NSLog("[Unolink] purchase(): amount is not a number. Not recorded.")
                break
            }
            Unolink.purchase(amount: amount, currency: args["currency"] as? String ?? "",
                             productId: args["productId"] as? String, properties: args["properties"] as? [String: Any])
        case "setUserId":
            Unolink.setUserId(args["userId"] as? String)
        case "flush":
            Unolink.flush()
        case "setEnabled":
            Unolink.setEnabled(args["enabled"] as? Bool ?? true)
        case "getInstallId":
            result(Unolink.installId)
            return
        default:
            result(FlutterMethodNotImplemented)
            return
        }
        result(nil)
    }
}
