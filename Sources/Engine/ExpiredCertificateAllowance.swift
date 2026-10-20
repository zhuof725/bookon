import Foundation
import Security

/// 段评服务器（七猫段评 qimao.gxom.lol / .mom）证书已过期：仅对白名单域名、且仅在「唯一问题是过期」时放行。
/// 其他域名、其他证书错误（域名不符、自签、吊销等）一律按系统默认拒绝。
final class ExpiredCertificateAllowance: NSObject, URLSessionTaskDelegate {
    static let delegate = ExpiredCertificateAllowance()
    static let hostSuffixes = ["gxom.lol", "gxom.mom"]

    static func isAllowed(host: String) -> Bool {
        let h = host.lowercased()
        return hostSuffixes.contains { h == $0 || h.hasSuffix("." + $0) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              Self.isAllowed(host: challenge.protectionSpace.host),
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil); return
        }
        if let credential = Self.credential(trust: trust, host: challenge.protectionSpace.host) {
            completionHandler(.useCredential, credential)
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }

    /// 校验通过返回 nil（走默认）；唯一问题是过期时把校验时间挪到证书有效期内重新评估，
    /// 域名与签发链仍照旧检查，通过则返回凭据。URLSession 与 WebView 共用。
    static func credential(trust: SecTrust, host: String? = nil) -> URLCredential? {
        var error: CFError?
        if SecTrustEvaluateWithError(trust, &error) { return nil }
        guard CFErrorGetCode(error) == Int(errSecCertificateExpired),
              let leaf = (SecTrustCopyCertificateChain(trust) as? [SecCertificate])?.first,
              let notBefore = notBefore(leaf) else { return nil }
        SecTrustSetVerifyDate(trust, notBefore.addingTimeInterval(86_400) as CFDate)
        guard SecTrustEvaluateWithError(trust, nil) else { return nil }
        if let host { DebugLog.add("◇\(host) 证书已过期，按白名单继续连接") }
        return URLCredential(trust: trust)
    }

    /// 从 DER 中取 notBefore（Validity 第一个 UTCTime/GeneralizedTime）。
    static func notBefore(_ cert: SecCertificate) -> Date? {
        let der = [UInt8](SecCertificateCopyData(cert) as Data)
        var i = 0
        while i + 2 < der.count {
            let tag = der[i], len = Int(der[i + 1])
            if (tag == 0x17 || tag == 0x18), len >= 13, len < 20, i + 2 + len <= der.count,
               let text = String(bytes: der[(i + 2)..<(i + 2 + len)], encoding: .ascii), text.hasSuffix("Z") {
                let f = DateFormatter()
                f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC")
                f.dateFormat = tag == 0x17 ? "yyMMddHHmmss'Z'" : "yyyyMMddHHmmss'Z'"
                if let d = f.date(from: text) { return d }
            }
            i += 1
        }
        return nil
    }
}
