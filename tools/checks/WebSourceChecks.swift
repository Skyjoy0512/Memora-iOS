import Foundation
import Security

@main
struct WebSourceChecks {
  static func main() async throws {
    if CommandLine.arguments.contains("--live") {
      let result = try await WebSourceFetcher().fetch(URL(string: "https://example.com/")!)
      precondition(result.content.title == "Example Domain" && result.content.blocks[0].text.contains("documentation"))
      print("WebSourceChecks live: public DNS -> pinned IP -> hostname TLS -> HTTP -> Example Domain text passed; no credentials")
      return
    }
    let certificateBytes = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
    let certificate = SecCertificateCreateWithData(nil, certificateBytes as CFData)!
    func trust() -> SecTrust {
      var result: SecTrust?
      precondition(SecTrustCreateWithCertificates(certificate, SecPolicyCreateSSL(true, "trusted.example.com" as CFString), &result) == errSecSuccess)
      return result!
    }
    let untrusted = trust()
    precondition(!PinnedHTTPSConnection.trusts(untrusted, hostname: "trusted.example.com"))
    let trusted = trust()
    precondition(SecTrustSetAnchorCertificates(trusted, [certificate] as CFArray) == errSecSuccess)
    precondition(SecTrustSetAnchorCertificatesOnly(trusted, true) == errSecSuccess)
    precondition(PinnedHTTPSConnection.trusts(trusted, hostname: "trusted.example.com"))
    precondition(!PinnedHTTPSConnection.trusts(trusted, hostname: "wrong.example.com"))
    let url = URL(string: "https://example.com/article?q=test")!
    for addresses in [[], ["127.0.0.1"], ["93.184.215.14", "10.0.0.1"], ["::1"], ["169.254.169.254"], ["2001:db8::1"], ["2001:20::1"], ["2001:2::1"], ["3fff::1"]] {
      do { _ = try WebSourceRequest(url: url, addresses: addresses); preconditionFailure("Unsafe DNS accepted") }
      catch WebSourceFailure.unsafeAddress {}
    }
    for value in ["http://example.com", "https://127.1/", "https://2130706433/", "https://[::1]/", "https://user:pass@example.com/", "https://a.local/", "https://example.com:8443/"] {
      do { _ = try WebSourceRequest.checkedURL(URL(string: value)!); preconditionFailure("Unsafe URL accepted") }
      catch WebSourceFailure.unsafeAddress {}
    }
    let request = try WebSourceRequest(url: url, addresses: ["93.184.215.14"])
    let sent = String(decoding: request.bytes, as: UTF8.self)
    precondition(request.address == "93.184.215.14" && request.host == "example.com")
    precondition(sent.contains("GET /article?q=test HTTP/1.1") && !sent.contains("Cookie:") && !sent.contains("Authorization:"))
    let html = """
      <!DOCTYPE html><html><head><title>会議 &amp; 資料</title><script>SECRET SCRIPT</scriptx>SECRET STILL SCRIPT</script><style>secret style</style></head>
      <body><nav>SECRET NAVIGATION</nav><main><article><h1>次回の決定</h1><p>Kenが資料を確認する。<strong>期限は金曜日。</strong></p>
      <p>金額 &#x31;200 &lt; 1500 &unknown;</p><p hidden>SECRET HIDDEN</p><p aria-hidden="true">SECRET ARIA</p></article></main>
      <iframe src="http://127.0.0.1/">SECRET FRAME</iframe><footer>SECRET FOOTER</footer></body></html>
      """
    let parsed = try WebSourceTextExtraction.read(Data(html.utf8), contentType: "text/html; charset=\"UTF-8\"")
    precondition(parsed.title == "会議 & 資料")
    let text = parsed.blocks.map(\.text).joined()
    precondition(text.contains("Kenが資料を確認する。期限は金曜日。") && text.contains("1200 < 1500 &unknown;") && !text.contains("SECRET"))
    let raw = Data("HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(html.utf8.count)\r\nSet-Cookie: ignored\r\nSet-Cookie: also-ignored\r\n\r\n\(html)".utf8)
    for cut in 1..<raw.count {
      var decoder = WebSourceHTTPDecoder()
      let first = try decoder.append(raw.prefix(cut), ended: false)
      let result = try first ?? decoder.append(raw.suffix(raw.count - cut), ended: true)
      precondition(result?.body == Data(html.utf8), "Fragmented HTTP response")
    }
    var chunked = WebSourceHTTPDecoder()
    let chunkResponse = Data("HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nTransfer-Encoding: chunked\r\n\r\n3\r\none\r\n3;safe=extension\r\ntwo\r\n0\r\n\r\n".utf8)
    var completed: WebSourceHTTPDecoder.Response?
    for byte in chunkResponse { completed = try chunked.append(Data([byte]), ended: false) ?? completed }
    precondition(completed?.body == Data("onetwo".utf8))
    for header in ["Content-Length: 1\r\nContent-Length: 1", "Content-Length: 3\r\nTransfer-Encoding: chunked", "Content-Length: 999999999", "Content-Encoding: gzip", "Content-Type: application/pdf"] {
      var decoder = WebSourceHTTPDecoder()
      do {
        let prefix = header.hasPrefix("Content-Type:") ? "" : "Content-Type: text/plain\r\n"
        _ = try decoder.append(Data("HTTP/1.1 200 OK\r\n\(prefix)\(header)\r\n\r\nx".utf8), ended: true)
        preconditionFailure("Unsafe response accepted")
      } catch is WebSourceFailure {}
    }
    do { _ = try WebSourceTextExtraction.read(Data("<script>only code</script>".utf8), contentType: "text/html"); preconditionFailure("Script accepted as text") }
    catch WebSourceFailure.noText {}
    let unicode = "<main>A" + String(repeating: "\u{301}", count: 200_000) + "</main>"
    let limited = try WebSourceTextExtraction.read(Data(unicode.utf8), contentType: "text/html")
    precondition(limited.blocks[0].text.utf8.count <= 256 * 1024 && limited.notice.contains("抜粋"))
    let bodyJSON = try JSONEncoder().encode(limited.blocks)
    precondition(bodyJSON.count < 2 * 1024 * 1024)
    let recorder = Recorder()
    let fetcher = WebSourceFetcher(resolve: { host in
      await recorder.resolved(host)
      return host == "private.example.com" ? ["127.0.0.1"] : ["93.184.215.14"]
    }, transfer: { request in
      await recorder.transferred(request)
      if request.url.path == "/article" {
        return .init(status: 302, headers: ["location": "/final"], body: Data())
      }
      return .init(status: 200, headers: ["content-type": "text/html"], body: Data(html.utf8))
    })
    let fetched = try await fetcher.fetch(url)
    precondition(fetched.finalURL.path == "/final" && fetched.content.title == parsed.title)
    let calls = await recorder.calls
    precondition(calls == ["dns:example.com", "ip:93.184.215.14", "dns:example.com", "ip:93.184.215.14"])
    let unsafe = WebSourceFetcher(resolve: fetcher.resolve, transfer: { request in
      await recorder.transferred(request)
      return .init(status: 302, headers: ["location": "https://private.example.com/secret"], body: Data())
    })
    do { _ = try await unsafe.fetch(url); preconditionFailure("Private redirect accepted") }
    catch WebSourceFailure.unsafeAddress {}
    let afterUnsafe = await recorder.calls
    precondition(afterUnsafe.suffix(3) == ["dns:example.com", "ip:93.184.215.14", "dns:private.example.com"])
    let cancelled = Task.detached {
      withUnsafeCurrentTask { $0?.cancel() }
      do { _ = try await fetcher.fetch(url); return false }
      catch is CancellationError { return true }
      catch { return false }
    }
    let stopped = await cancelled.value
    precondition(stopped)
    let pendingRecorder = Recorder()
    let pending = WebSourceFetcher(resolve: { _ in ["93.184.215.14"] }, transfer: { request in
      await pendingRecorder.transferred(request)
      try await Task.sleep(for: .seconds(30))
      return .init(status: 200, headers: ["content-type": "text/plain"], body: Data("late reply".utf8))
    })
    let running = Task { try await pending.fetch(url) }
    while await pendingRecorder.calls.isEmpty { await Task.yield() }
    running.cancel()
    do { _ = try await running.value; preconditionFailure("In-flight cancellation ignored") }
    catch is CancellationError {}
    let pendingCalls = await pendingRecorder.calls
    precondition(pendingCalls.count == 1)
    let loop = WebSourceFetcher(resolve: { _ in ["93.184.215.14"] }, transfer: { _ in
      .init(status: 302, headers: ["location": url.absoluteString], body: Data())
    })
    do { _ = try await loop.fetch(url); preconditionFailure("Redirect loop accepted") }
    catch WebSourceFailure.redirects {}
    let refused = WebSourceFetcher(resolve: { _ in ["93.184.215.14"] }, transfer: { _ in
      .init(status: 429, headers: [:], body: Data())
    })
    do { _ = try await refused.fetch(url); preconditionFailure("HTTP error accepted") }
    catch WebSourceFailure.status(429) {}
    print("WebSourceChecks: passed (fixed public endpoint, redirect DNS, secret-free GET, split/chunked/bounded HTTP, nonexecuting HTML, entities, Unicode, cancellation; mock transport, no network)")
  }

  actor Recorder {
    var calls: [String] = []
    func resolved(_ host: String) { calls.append("dns:" + host) }
    func transferred(_ request: WebSourceRequest) { calls.append("ip:" + request.address) }
  }
}
