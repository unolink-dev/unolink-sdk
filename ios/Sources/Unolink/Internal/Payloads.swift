import Foundation

/// Builds request bodies and reads responses exactly as contract/schemas describe them.
enum Payloads {
    static let maxProperties = 20
    static let maxString = 200
    private static let namePattern = try! NSRegularExpression(pattern: "^[A-Za-z][A-Za-z0-9_.]{0,63}$")
    private static let currencyPattern = try! NSRegularExpression(pattern: "^[A-Za-z]{3}$")

    static func isValidName(_ name: String) -> Bool { matches(namePattern, name) }
    static func isValidCurrency(_ currency: String) -> Bool { matches(currencyPattern, currency) }

    private static func matches(_ regex: NSRegularExpression, _ s: String) -> Bool {
        regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }

    static func timestamp(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: date)
    }

    /// Keeps string (trimmed to 200), number and boolean values; anything else is dropped with a warning.
    static func properties(_ input: [String: Any]?, log: Logger) -> [String: Any]? {
        guard let input = input, !input.isEmpty else { return nil }
        var out: [String: Any] = [:]
        for (key, value) in input.sorted(by: { $0.key < $1.key }) {
            if out.count >= maxProperties {
                log.warn("Only the first \(maxProperties) event properties are kept.")
                break
            }
            guard !key.isEmpty, key.count <= 64 else {
                log.warn("Property name \"\(key)\" must be 1-64 characters; dropped.")
                continue
            }
            switch value {
            case let s as String: out[key] = String(s.prefix(maxString))
            // No `case let b as Bool`: Swift reads any NSNumber 0 or 1 as a Bool, and React Native and Flutter hand every
            // number over as NSNumber. A real Bool (Swift or bridged) is an NSNumber of CFBoolean type, caught here.
            case let n as NSNumber where CFGetTypeID(n) == CFBooleanGetTypeID(): out[key] = n.boolValue
            case let d as Decimal: out[key] = NSDecimalNumber(decimal: d)
            case let d as Double where !d.isFinite: log.warn("Property \"\(key)\" is not a finite number; dropped.")
            case let f as Float where !f.isFinite: log.warn("Property \"\(key)\" is not a finite number; dropped.")
            case let n as NSNumber: out[key] = n
            case is NSNull: break
            default: log.warn("Property \"\(key)\" must be a string, number or boolean; dropped.")
            }
        }
        return out.isEmpty ? nil : out
    }

    /// "49.99" from a Decimal; nil when negative or more precise than 6 decimals.
    static func amount(_ amount: Decimal) -> String? {
        guard amount >= 0 else { return nil }
        var value = amount
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 6, .plain)
        guard rounded == amount else { return nil }
        let number = NSDecimalNumber(decimal: amount)
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 6
        return formatter.string(from: number)
    }

    static func event(id: String, name: String, at date: Date, properties: [String: Any]?, revenue: (amount: String, currency: String)?) -> String {
        var event: [String: Any] = ["id": id, "name": name, "timestamp": timestamp(date)]
        if let p = properties { event["properties"] = p }
        if let r = revenue { event["revenue"] = ["amount": r.amount, "currency": r.currency.uppercased()] }
        return json(event)
    }

    static func install(installId: String, device: DeviceInfo, userId: String?) -> String {
        var body: [String: Any] = [
            "installId": installId,
            "platform": device.platform,
            "sdk": ["name": device.sdkName, "version": device.sdkVersion],
            "isDebug": device.isDebug,
        ]
        if let v = device.osVersion { body["osVersion"] = String(v.prefix(32)) }
        if let v = device.appVersion { body["appVersion"] = String(v.prefix(32)) }
        if let v = device.deviceClass { body["deviceClass"] = v }
        if let v = device.locale { body["locale"] = String(v.prefix(35)) }
        // "" (not left out) when there's no user: after setUserId(nil) the server then clears this install's current user.
        body["userId"] = userId ?? ""
        return json(body)
    }

    static func events(installId: String, events: [String], userId: String?) -> String {
        var head = "{\"installId\":\(json(installId))"
        if let u = userId { head += ",\"userId\":\(json(u))" }
        return head + ",\"events\":[\(events.joined(separator: ","))]}"
    }

    /// The deferred deep link from a /v1/install response, when the install was attributed to a link.
    static func deepLink(fromInstall body: String?) -> UnolinkDeepLink? {
        guard let root = object(body), let a = root["attribution"] as? [String: Any],
              a["status"] as? String == "attributed", let clickId = a["clickId"] as? String else { return nil }
        let link = a["link"] as? [String: Any]
        return UnolinkDeepLink(
            deepLink: a["deepLink"] as? String,
            params: (a["params"] as? [String: String]) ?? [:],
            linkSlug: link?["slug"] as? String,
            clickId: clickId)
    }

    /// The code of an error response (RFC 9457 problem details), e.g. "install_required".
    static func problemCode(_ body: String?) -> String? { object(body)?["code"] as? String }

    static func rejected(_ body: String?) -> [[String: Any]] { (object(body)?["rejected"] as? [[String: Any]]) ?? [] }

    static func object(_ body: String?) -> [String: Any]? {
        guard let data = body?.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func json(_ value: Any) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .sortedKeys, .withoutEscapingSlashes])) ?? Data("null".utf8)
        return String(decoding: data, as: UTF8.self)
    }
}
