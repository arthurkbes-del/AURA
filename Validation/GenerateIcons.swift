// SPDX-License-Identifier: GPL-3.0-or-later
import AuraCore
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

@main struct GenerateIcons {
    static func main() throws {
        let catalog = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Aura/Aura/Resources/Assets.xcassets", isDirectory: true)
        let destination = catalog.appendingPathComponent("AppIcon.appiconset", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8,
                                bytesPerRow: 4096, space: space,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.translateBy(x: 0, y: 1024); context.scaleBy(x: 1, y: -1)
        let panel = CGPath(roundedRect: CGRect(x: 12, y: 12, width: 1000, height: 1000),
                           cornerWidth: 220, cornerHeight: 220, transform: nil)
        context.saveGState(); context.addPath(panel); context.clip()
        let gradient = CGGradient(colorsSpace: space, colors: [
            CGColor(srgbRed: 0.17, green: 0.19, blue: 0.22, alpha: 1),
            CGColor(srgbRed: 0.025, green: 0.035, blue: 0.07, alpha: 1)
        ] as CFArray, locations: [0, 1])!
        context.drawLinearGradient(gradient, start: CGPoint(x: 350, y: 0), end: CGPoint(x: 600, y: 1024),
                                   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        context.restoreGState()
        context.addPath(panel); context.setStrokeColor(CGColor(srgbRed: 0.27, green: 0.29, blue: 0.32, alpha: 1))
        context.setLineWidth(3); context.strokePath()
        let wave = AuraSymbol.path(in: CGRect(x: 180, y: 270, width: 660, height: 480))
        context.setLineCap(.round); context.setLineJoin(.round)
        context.setShadow(offset: .zero, blur: 44, color: CGColor(srgbRed: 0.03, green: 0.38, blue: 1, alpha: 0.85))
        context.addPath(wave); context.setLineWidth(31)
        context.setStrokeColor(CGColor(srgbRed: 0.04, green: 0.4, blue: 1, alpha: 1)); context.strokePath()
        context.setShadow(offset: .zero, blur: 0, color: nil)
        context.saveGState(); context.addPath(wave); context.setLineWidth(26)
        context.replacePathWithStrokedPath(); context.clip()
        let waveGradient = CGGradient(colorsSpace: space, colors: [
            CGColor(srgbRed: 0.04, green: 0.35, blue: 1, alpha: 1),
            CGColor(srgbRed: 0.3, green: 0.95, blue: 1, alpha: 1)
        ] as CFArray, locations: [0, 1])!
        context.drawLinearGradient(waveGradient, start: CGPoint(x: 200, y: 750), end: CGPoint(x: 850, y: 300), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        context.restoreGState()
        let image = context.makeImage()!
        var images: [[String: String]] = []
        for points in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let pixels = points * scale
                let resized = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8,
                                        bytesPerRow: pixels * 4, space: space,
                                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                resized.interpolationQuality = .high
                resized.draw(image, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
                let filename = "icon_\(points)x\(points)@\(scale)x.png"
                let output = CGImageDestinationCreateWithURL(destination.appendingPathComponent(filename) as CFURL, UTType.png.identifier as CFString, 1, nil)!
                CGImageDestinationAddImage(output, resized.makeImage()!, nil)
                guard CGImageDestinationFinalize(output) else { throw CocoaError(.fileWriteUnknown) }
                images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": filename])
            }
        }
        let info: [String: Any] = ["author": "xcode", "version": 1]
        try JSONSerialization.data(withJSONObject: ["images": images, "info": info], options: [.prettyPrinted, .sortedKeys])
            .write(to: destination.appendingPathComponent("Contents.json"))
        try JSONSerialization.data(withJSONObject: ["info": info], options: [.prettyPrinted, .sortedKeys])
            .write(to: catalog.appendingPathComponent("Contents.json"))
        // MenuBarExtra's native image initializer consumes named asset images.
        // Transparent monochrome masks adapt to macOS's menu-bar contrast.
        for state in ["Stopped", "Processing", "Bypassed", "Error"] {
            let imageset = catalog.appendingPathComponent("AuraStatus\(state).imageset", isDirectory: true)
            try FileManager.default.createDirectory(at: imageset, withIntermediateDirectories: true)
            var entries: [[String: String]] = []
            for scale in [1, 2, 3] {
                let width = 22 * scale, height = 18 * scale
                let menu = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                     bytesPerRow: width * 4, space: space,
                                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                menu.translateBy(x: 0, y: CGFloat(height))
                menu.scaleBy(x: CGFloat(scale), y: -CGFloat(scale))
                let color: CGColor
                if state == "Processing" { color = CGColor(srgbRed: 0, green: 0.48, blue: 1, alpha: 1) }
                else if state == "Error" { color = CGColor(srgbRed: 1, green: 0.23, blue: 0.19, alpha: 1) }
                else { color = CGColor(gray: 0, alpha: state == "Stopped" ? 0.65 : 0.6) }
                menu.setStrokeColor(color); menu.setFillColor(color)
                menu.setLineWidth(1.6); menu.setLineCap(.round); menu.setLineJoin(.round)
                menu.addPath(AuraSymbol.path(in: CGRect(x: 1, y: 1, width: 20, height: 16)))
                menu.strokePath()
                if state == "Stopped" { menu.fill(CGRect(x: 18, y: 14, width: 3, height: 3)) }
                if state == "Bypassed" {
                    menu.setStrokeColor(CGColor(gray: 0, alpha: 1))
                    menu.move(to: CGPoint(x: 4, y: 2)); menu.addLine(to: CGPoint(x: 19, y: 16)); menu.strokePath()
                }
                if state == "Error" {
                    menu.fillEllipse(in: CGRect(x: 15, y: 10, width: 7, height: 7))
                    menu.setStrokeColor(CGColor(gray: 1, alpha: 1)); menu.setLineWidth(0.8)
                    menu.move(to: CGPoint(x: 18.5, y: 11.5)); menu.addLine(to: CGPoint(x: 18.5, y: 13.8)); menu.strokePath()
                    menu.setFillColor(CGColor(gray: 1, alpha: 1)); menu.fillEllipse(in: CGRect(x: 18.05, y: 14.7, width: 0.9, height: 0.9))
                }
                let filename = "wave@\(scale)x.png"
                let output = CGImageDestinationCreateWithURL(imageset.appendingPathComponent(filename) as CFURL, UTType.png.identifier as CFString, 1, nil)!
                CGImageDestinationAddImage(output, menu.makeImage()!, nil)
                guard CGImageDestinationFinalize(output) else { throw CocoaError(.fileWriteUnknown) }
                entries.append(["idiom": "universal", "scale": "\(scale)x", "filename": filename])
            }
            let template = state == "Stopped" || state == "Bypassed"
            try JSONSerialization.data(withJSONObject: ["images": entries, "info": info,
                "properties": ["template-rendering-intent": template ? "template" : "original"]],
                options: [.prettyPrinted, .sortedKeys]).write(to: imageset.appendingPathComponent("Contents.json"))
        }
        print("Generated ten macOS icon sizes from the native AuraSymbol vector: \(destination.path)")
        print("Generated four menu-bar state image sets at 1x/2x/3x.")
    }
}
