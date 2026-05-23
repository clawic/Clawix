import SwiftUI
import WebKit

// MARK: - Mermaid diagram
//
// Renders a ```mermaid fenced block as a diagram using mermaid.js inside a
// transparent WKWebView. The diagram height is measured and reported back so
// the view sizes to content. If anything fails (offline, parse error), it
// falls back to showing the raw source as a normal code block — so it can
// never break message rendering.

struct MermaidDiagramView: View {
    let code: String
    let ordinal: Int

    @State private var height: CGFloat = 48
    @State private var failed = false

    var body: some View {
        if failed {
            AssistantCodeBlockView(language: "mermaid", code: code, ordinal: ordinal)
        } else {
            MermaidWebView(code: code, height: $height, failed: $failed)
                .frame(height: height)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Palette.popupStroke, lineWidth: Palette.popupStrokeWidth)
                )
        }
    }
}

private struct MermaidWebView: NSViewRepresentable {
    let code: String
    @Binding var height: CGFloat
    @Binding var failed: Bool

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "size")
        config.userContentController.add(context.coordinator, name: "fail")
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.underPageBackgroundColor = .clear
        web.setValue(false, forKey: "drawsBackground")
        return web
    }

    func updateNSView(_ web: WKWebView, context: Context) {
        if context.coordinator.lastCode != code {
            context.coordinator.lastCode = code
            web.loadHTMLString(Self.html(for: code), baseURL: nil)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        let parent: MermaidWebView
        var lastCode: String?
        init(_ parent: MermaidWebView) { self.parent = parent }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            switch message.name {
            case "size":
                if let value = message.body as? Double {
                    DispatchQueue.main.async { self.parent.height = max(40, CGFloat(value)) }
                }
            case "fail":
                DispatchQueue.main.async { self.parent.failed = true }
            default:
                break
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async { self.parent.failed = true }
        }
    }

    static func html(for code: String) -> String {
        let escaped = code
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        return """
        <!DOCTYPE html><html><head><meta charset="utf-8">
        <style>
          html, body { margin: 0; padding: 0; background: transparent; }
          .mermaid { background: transparent; }
        </style></head>
        <body>
          <pre class="mermaid">\(escaped)</pre>
          <script src="https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.min.js"></script>
          <script>
            function report() {
              try {
                var h = document.body.scrollHeight;
                window.webkit.messageHandlers.size.postMessage(h);
              } catch (e) {}
            }
            try {
              mermaid.initialize({ startOnLoad: false, theme: 'dark', securityLevel: 'strict' });
              mermaid.run().then(report).catch(function() {
                window.webkit.messageHandlers.fail.postMessage(1);
              });
            } catch (e) {
              window.webkit.messageHandlers.fail.postMessage(1);
            }
            setTimeout(function() {
              if (!document.querySelector('svg')) {
                window.webkit.messageHandlers.fail.postMessage(1);
              } else { report(); }
            }, 4000);
          </script>
        </body></html>
        """
    }
}
