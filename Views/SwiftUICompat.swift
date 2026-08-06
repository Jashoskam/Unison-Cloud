import SwiftUI

// Compatibility helpers for older SwiftUI / SDK combinations.
func unisonColor(from hex: String) -> Color {
    let hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
    var hexValue: UInt64 = 0
    guard Scanner(string: hexSanitized).scanHexInt64(&hexValue) else {
        return .white
    }

    let length = hexSanitized.count
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    if length == 6 {
        red = Double((hexValue & 0xFF0000) >> 16) / 255.0
        green = Double((hexValue & 0x00FF00) >> 8) / 255.0
        blue = Double(hexValue & 0x0000FF) / 255.0
        alpha = 1.0
    } else if length == 8 {
        red = Double((hexValue & 0xFF000000) >> 24) / 255.0
        green = Double((hexValue & 0x00FF0000) >> 16) / 255.0
        blue = Double((hexValue & 0x0000FF00) >> 8) / 255.0
        alpha = Double(hexValue & 0x000000FF) / 255.0
    } else {
        return .white
    }

    return Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
}

extension Color {
    static let zinc300 = Color(red: 0.81, green: 0.82, blue: 0.84)
    static let zinc400 = Color(red: 0.70, green: 0.71, blue: 0.74)
    static let emerald = Color(red: 0.06, green: 0.73, blue: 0.51)
    static let amber = Color(red: 0.96, green: 0.62, blue: 0.18)

    init?(hex: String) {
        let hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        guard !hexSanitized.isEmpty else { return nil }

        var hexValue: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&hexValue) else {
            return nil
        }

        let length = hexSanitized.count
        let red: Double
        let green: Double
        let blue: Double
        let alpha: Double

        if length == 6 {
            red = Double((hexValue & 0xFF0000) >> 16) / 255.0
            green = Double((hexValue & 0x00FF00) >> 8) / 255.0
            blue = Double(hexValue & 0x0000FF) / 255.0
            alpha = 1.0
        } else if length == 8 {
            red = Double((hexValue & 0xFF000000) >> 24) / 255.0
            green = Double((hexValue & 0x00FF0000) >> 16) / 255.0
            blue = Double((hexValue & 0x0000FF00) >> 8) / 255.0
            alpha = Double(hexValue & 0x000000FF) / 255.0
        } else {
            return nil
        }

        self = Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}

private struct EdgeBorder: Shape {
    var width: CGFloat
    var edges: [Edge]
    var color: Color

    func path(in rect: CGRect) -> Path {
        var path = Path()
        if edges.contains(.top) {
            path.addRect(CGRect(x: 0, y: 0, width: rect.width, height: width))
        }
        if edges.contains(.bottom) {
            path.addRect(CGRect(x: 0, y: rect.height - width, width: rect.width, height: width))
        }
        if edges.contains(.leading) {
            path.addRect(CGRect(x: 0, y: 0, width: width, height: rect.height))
        }
        if edges.contains(.trailing) {
            path.addRect(CGRect(x: rect.width - width, y: 0, width: width, height: rect.height))
        }
        return path
    }
}

extension View {
    func border(width: CGFloat, edges: [Edge], color: Color) -> some View {
        overlay(
            EdgeBorder(width: width, edges: edges, color: color)
                .fill(color)
        )
    }
}

#if os(macOS)
public struct VisualEffectView: NSViewRepresentable {
    public let material: NSVisualEffectView.Material
    public let blendingMode: NSVisualEffectView.BlendingMode
    
    public init(material: NSVisualEffectView.Material = .hudWindow, blendingMode: NSVisualEffectView.BlendingMode = .withinWindow) {
        self.material = material
        self.blendingMode = blendingMode
    }
    
    public func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    public func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

import WebKit

public struct HTMLOrbView: NSViewRepresentable {
    var audioLevel: Float = 0.0
    
    public init(audioLevel: Float = 0.0) {
        self.audioLevel = audioLevel
    }
    
    public func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.setValue(false, forKey: "drawsBackground")
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(true, forKey: "drawsTransparentBackground")
        
        let htmlContent = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
          body, html { margin: 0; padding: 0; width: 100%; height: 100%; overflow: hidden; background: transparent; display: flex; align-items: center; justify-content: center; }
          canvas { width: 100%; height: 100%; display: block; border-radius: 50%; }
        </style>
        </head>
        <body>
        <canvas id="orbCanvas"></canvas>
        <script>
          const canvas = document.getElementById('orbCanvas');
          const ctx = canvas.getContext('2d');
          let width, height, dpr;
          let time = 0;
          let audioLevel = 0.0;

          function resize() {
            dpr = window.devicePixelRatio || 2;
            width = canvas.clientWidth * dpr;
            height = canvas.clientHeight * dpr;
            canvas.width = width;
            canvas.height = height;
          }
          window.addEventListener('resize', resize);
          resize();

          function draw() {
            time += 0.03;
            ctx.clearRect(0, 0, width, height);

            const cx = width / 2;
            const cy = height / 2;
            const baseRadius = Math.min(width, height) * 0.38;

            // 1. Ambient Glow Aura
            const auraRadius = baseRadius * (1.35 + Math.sin(time * 2) * 0.08 + audioLevel * 0.35);
            const auraGrad = ctx.createRadialGradient(cx, cy, 0, cx, cy, auraRadius);
            auraGrad.addColorStop(0, 'rgba(6, 182, 212, 0.5)');
            auraGrad.addColorStop(0.5, 'rgba(168, 85, 247, 0.25)');
            auraGrad.addColorStop(1, 'rgba(0, 0, 0, 0)');
            ctx.fillStyle = auraGrad;
            ctx.beginPath();
            ctx.arc(cx, cy, auraRadius, 0, Math.PI * 2);
            ctx.fill();

            // 2. Liquid Core Base
            const coreGrad = ctx.createRadialGradient(cx - baseRadius * 0.2, cy - baseRadius * 0.2, 0, cx, cy, baseRadius);
            coreGrad.addColorStop(0, '#06b6d4');
            coreGrad.addColorStop(0.4, '#3b82f6');
            coreGrad.addColorStop(0.8, '#8b5cf6');
            coreGrad.addColorStop(1, '#030712');

            ctx.save();
            ctx.beginPath();
            ctx.arc(cx, cy, baseRadius, 0, Math.PI * 2);
            ctx.fillStyle = coreGrad;
            ctx.shadowColor = '#00f0ff';
            ctx.shadowBlur = 16 * dpr;
            ctx.fill();
            ctx.restore();

            // 3. Fluid Wave Ripples
            for (let i = 0; i < 3; i++) {
              ctx.save();
              ctx.beginPath();
              const waveAngle = time * (1.2 + i * 0.5) + i * 2.1;
              const offsetX = Math.cos(waveAngle) * baseRadius * 0.25;
              const offsetY = Math.sin(waveAngle) * baseRadius * 0.25;

              const waveGrad = ctx.createLinearGradient(
                cx + offsetX, cy + offsetY,
                cx - offsetX, cy - offsetY
              );
              if (i === 0) {
                waveGrad.addColorStop(0, 'rgba(6, 182, 212, 0.7)');
                waveGrad.addColorStop(1, 'rgba(168, 85, 247, 0.1)');
              } else if (i === 1) {
                waveGrad.addColorStop(0, 'rgba(16, 185, 129, 0.6)');
                waveGrad.addColorStop(1, 'rgba(59, 130, 246, 0.1)');
              } else {
                waveGrad.addColorStop(0, 'rgba(236, 72, 153, 0.5)');
                waveGrad.addColorStop(1, 'rgba(6, 182, 212, 0.1)');
              }

              ctx.fillStyle = waveGrad;
              ctx.arc(cx + offsetX, cy + offsetY, baseRadius * (0.8 - i * 0.15), 0, Math.PI * 2);
              ctx.globalCompositeOperation = 'screen';
              ctx.fill();
              ctx.restore();
            }

            // 4. Specular Gloss Reflection Rim
            ctx.save();
            const glossGrad = ctx.createRadialGradient(cx - baseRadius * 0.35, cy - baseRadius * 0.35, 0, cx, cy, baseRadius);
            glossGrad.addColorStop(0, 'rgba(255, 255, 255, 0.7)');
            glossGrad.addColorStop(0.3, 'rgba(255, 255, 255, 0.15)');
            glossGrad.addColorStop(1, 'rgba(255, 255, 255, 0)');
            ctx.fillStyle = glossGrad;
            ctx.beginPath();
            ctx.arc(cx, cy, baseRadius, 0, Math.PI * 2);
            ctx.fill();
            ctx.restore();

            // 5. Outer Glass Edge Ring
            ctx.strokeStyle = 'rgba(255, 255, 255, 0.35)';
            ctx.lineWidth = 1.2 * dpr;
            ctx.beginPath();
            ctx.arc(cx, cy, baseRadius, 0, Math.PI * 2);
            ctx.stroke();

            requestAnimationFrame(draw);
          }
          draw();

          window.updateAudioLevel = function(level) {
            audioLevel = level;
          };
        </script>
        </body>
        </html>
        """
        webView.loadHTMLString(htmlContent, baseURL: nil)
        return webView
    }
    
    public func updateNSView(_ webView: WKWebView, context: Context) {
        let js = "if (window.updateAudioLevel) { window.updateAudioLevel(\(audioLevel)); }"
        webView.evaluateJavaScript(js, completionHandler: nil)
    }
}
#endif

