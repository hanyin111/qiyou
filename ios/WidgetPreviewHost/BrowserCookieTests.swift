import UIKit
import WebKit
import XCTest
@testable import WidgetPreviewHost

final class BrowserCookieTests: XCTestCase {
  func testPrivateHttpOnlyCookiesComeFromBoundWebView() throws {
    let root = UIView(frame: CGRect(x: 0, y: 0, width: 400, height: 400))
    let window = UIWindow(frame: root.frame)
    let host = UIViewController()
    host.view = root
    window.rootViewController = host
    window.makeKeyAndVisible()
    defer { window.isHidden = true }
    let firstConfig = WKWebViewConfiguration()
    firstConfig.websiteDataStore = .nonPersistent()
    let secondConfig = WKWebViewConfiguration()
    secondConfig.websiteDataStore = .nonPersistent()
    let first = WKWebView(frame: root.bounds, configuration: firstConfig)
    let second = WKWebView(frame: root.bounds, configuration: secondConfig)
    root.addSubview(first)
    root.addSubview(second)
    let loaded = expectation(description: "Two isolated pages loaded")
    loaded.expectedFulfillmentCount = 2
    let navigation = CookiePageNavigation(loaded)
    first.navigationDelegate = navigation
    second.navigationDelegate = navigation
    let url = try XCTUnwrap(URL(string: "https://user.mihoyo.com/"))
    for view in [first, second] {
      view.loadHTMLString("<html><body>Local synthetic fixture</body></html>", baseURL: url)
    }
    wait(for: [loaded], timeout: 15)
    XCTAssertEqual(first.url?.host, url.host)
    let cookie = try XCTUnwrap(HTTPCookie(properties: [
      .name: "qiyou_private_fixture", .value: "only-first-session",
      .domain: "user.mihoyo.com", .path: "/", .secure: "TRUE",
      HTTPCookiePropertyKey("HttpOnly"): "TRUE"
    ]))
    XCTAssertTrue(cookie.isHTTPOnly)
    let otherCookie = try XCTUnwrap(HTTPCookie(properties: [
      .name: cookie.name, .value: "other-session", .domain: cookie.domain, .path: "/"
    ]))
    let decoyCookie = try XCTUnwrap(HTTPCookie(properties: [
      .name: cookie.name, .value: "wrong-default-store", .domain: cookie.domain, .path: "/"
    ]))
    let stored = expectation(description: "Synthetic cookies installed")
    stored.expectedFulfillmentCount = 3
    first.configuration.websiteDataStore.httpCookieStore.setCookie(cookie) { stored.fulfill() }
    second.configuration.websiteDataStore.httpCookieStore.setCookie(otherCookie) { stored.fulfill() }
    WKWebsiteDataStore.default().httpCookieStore.setCookie(decoyCookie) { stored.fulfill() }
    wait(for: [stored], timeout: 8)
    defer { WKWebsiteDataStore.default().httpCookieStore.delete(decoyCookie) }
    let nonce = "0123456789abcdef0123456789abcdef"
    let bound = expectation(description: "Exact WebView bound")
    first.evaluateJavaScript("window.__qiyouSessionReadNonce = '\(nonce)'") { _, error in
      XCTAssertNil(error); bound.fulfill()
    }
    wait(for: [bound], timeout: 8)
    let reader = BrowserCookieBridge(roots: { [root] })
    let read = expectation(description: "Private HttpOnly cookie read")
    reader.read(nonce: nonce, urls: [url.absoluteString]) { response in
      switch response {
      case .success(let cookies): XCTAssertEqual(cookies[cookie.name], cookie.value)
      case .failure(let error): XCTFail("Private cookie read failed: \(error)")
      }
      read.fulfill()
    }
    wait(for: [read], timeout: 8)
    let absent = expectation(description: "No fallback for unmatched WebView")
    reader.read(nonce: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", urls: [url.absoluteString]) { response in
      if case .success = response { XCTFail("Must not read another session or default store") }
      absent.fulfill()
    }
    wait(for: [absent], timeout: 8)
  }

  func testCookieDomainPathAndOfficialURLBoundaries() throws {
    let cookie = try XCTUnwrap(HTTPCookie(properties: [
      .name: "fixture", .value: "synthetic", .domain: ".mihoyo.com", .path: "/account", .secure: "TRUE"
    ]))
    XCTAssertTrue(BrowserCookieBridge.matches(cookie, url: URL(string: "https://user.mihoyo.com/account/details")!))
    for raw in ["https://evil-mihoyo.com/account", "https://user.mihoyo.com/accounting", "http://user.mihoyo.com/account"] {
      XCTAssertFalse(BrowserCookieBridge.matches(cookie, url: URL(string: raw)!))
    }
    for raw in ["https://user.mihoyo.com/", "https://www.kurobbs.com/mc/"] {
      XCTAssertTrue(BrowserCookieBridge.isOfficial(URL(string: raw)!))
    }
    for raw in ["https://mihoyo.com.evil.example/", "http://user.mihoyo.com/", "https://user:pass@user.mihoyo.com/", "file:///tmp/file"] {
      XCTAssertFalse(BrowserCookieBridge.isOfficial(URL(string: raw)!))
    }
    var readRoots = false
    let reader = BrowserCookieBridge(roots: { readRoots = true; return [] })
    reader.read(nonce: "0123456789abcdef0123456789abcdef", urls: ["https://evil.example/"]) { response in
      if case .success = response { XCTFail("Untrusted target accepted") }
    }
    XCTAssertFalse(readRoots)
  }
}

private final class CookiePageNavigation: NSObject, WKNavigationDelegate {
  private let loaded: XCTestExpectation
  init(_ loaded: XCTestExpectation) { self.loaded = loaded }
  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loaded.fulfill() }
  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
    XCTFail("Synthetic page failed to load"); loaded.fulfill()
  }
}
