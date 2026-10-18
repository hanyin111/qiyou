import Foundation
import UIKit
import WebKit

// Read the current WKWebView's private cookie jar, including HttpOnly cookies.
// No default-store fallback, plugin internals, form inspection or logging.
final class BrowserCookieBridge {
  enum Failure: Error { case invalidRequest, sessionUnavailable }
  private let roots: () -> [UIView]
  private static let domains = [
    "mihoyo.com", "miyoushe.com", "kurobbs.com", "kurogame.com",
    "tajiduo.com", "wanmei.com", "laohu.com"
  ]

  init(roots: @escaping () -> [UIView]) { self.roots = roots }

  static func isOfficial(_ url: URL) -> Bool {
    guard url.scheme == "https", let host = url.host?.lowercased(),
          url.user == nil, url.password == nil else { return false }
    return domains.contains { host == $0 || host.hasSuffix("." + $0) }
  }

  private func webViews(in root: UIView) -> [WKWebView] {
    if let webView = root as? WKWebView { return [webView] }
    return root.subviews.flatMap { webViews(in: $0) }
  }

  func read(nonce: String, urls: [String],
            completion: @escaping (Result<[String: String], Error>) -> Void) {
    guard nonce.range(of: "^[a-zA-Z0-9-]{16,64}$", options: .regularExpression) != nil,
          !urls.isEmpty, urls.count <= 8 else {
      completion(.failure(Failure.invalidRequest)); return
    }
    let targets = urls.compactMap { URL(string: $0) }
    guard targets.count == urls.count, targets.allSatisfy(Self.isOfficial) else {
      completion(.failure(Failure.invalidRequest)); return
    }
    var seen = Set<ObjectIdentifier>()
    let candidates = roots().flatMap { webViews(in: $0) }.filter {
      seen.insert(ObjectIdentifier($0)).inserted && $0.url.map(Self.isOfficial) == true
    }
    guard !candidates.isEmpty else {
      completion(.failure(Failure.sessionUnavailable)); return
    }
    var finished = false
    func finish(_ result: Result<[String: String], Error>) {
      guard !finished else { return }
      finished = true
      completion(result)
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
      finish(.failure(Failure.sessionUnavailable))
    }
    var remaining = candidates.count
    var matches: [WKWebView] = []
    for webView in candidates {
      webView.evaluateJavaScript("window.__qiyouSessionReadNonce") { value, _ in
        guard !finished else { return }
        if value as? String == nonce { matches.append(webView) }
        remaining -= 1
        guard remaining == 0 else { return }
        guard matches.count == 1, let selected = matches.first,
              selected.url.map(Self.isOfficial) == true else {
          finish(.failure(Failure.sessionUnavailable)); return
        }
        selected.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
          guard selected.url.map(Self.isOfficial) == true else {
            finish(.failure(Failure.sessionUnavailable)); return
          }
          var values: [String: String] = [:]
          for url in targets {
            for cookie in cookies where Self.matches(cookie, url: url) {
              if values[cookie.name] == nil { values[cookie.name] = cookie.value }
            }
          }
          finish(.success(values))
        }
      }
    }
  }

  static func matches(_ cookie: HTTPCookie, url: URL) -> Bool {
    guard let host = url.host?.lowercased(),
          cookie.expiresDate.map({ $0 > Date() }) ?? true,
          !cookie.isSecure || url.scheme == "https" else { return false }
    let domain = cookie.domain.lowercased()
    let cleanDomain = domain.hasPrefix(".") ? String(domain.dropFirst()) : domain
    guard host == cleanDomain || (domain.hasPrefix(".") && host.hasSuffix(domain)) else { return false }
    let path = url.path.isEmpty ? "/" : url.path
    return path == cookie.path || (path.hasPrefix(cookie.path) &&
      (cookie.path.hasSuffix("/") || path.dropFirst(cookie.path.count).hasPrefix("/")))
  }
}
