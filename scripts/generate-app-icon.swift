#!/usr/bin/env swift

import AppKit
import Foundation

private extension NSBezierPath {
    var cgPath: CGPath {
        let path = CGMutablePath()
        var points = [NSPoint](repeating: .zero, count: 3)

        for index in 0..<elementCount {
            switch element(at: index, associatedPoints: &points) {
            case .moveTo:
                path.move(to: points[0])
            case .lineTo:
                path.addLine(to: points[0])
            case .curveTo:
                path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .quadraticCurveTo:
                path.addQuadCurve(to: points[1], control: points[0])
            case .cubicCurveTo:
                path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .closePath:
                path.closeSubpath()
            @unknown default:
                break
            }
        }

        return path
    }
}

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: generate-app-icon.swift <output.png>\n", stderr)
    exit(64)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let canvasSize = CGSize(width: 1024, height: 1024)
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(canvasSize.width),
    pixelsHigh: Int(canvasSize.height),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fputs("Could not create bitmap.\n", stderr)
    exit(1)
}

guard let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fputs("Could not create graphics context.\n", stderr)
    exit(1)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = graphicsContext
defer {
    NSGraphicsContext.restoreGraphicsState()
}

let context = graphicsContext.cgContext

context.setAllowsAntialiasing(true)
context.setShouldAntialias(true)

let bounds = CGRect(origin: .zero, size: canvasSize)
let outerRect = bounds.insetBy(dx: 72, dy: 72)
let backgroundPath = NSBezierPath(roundedRect: outerRect, xRadius: 230, yRadius: 230)

context.saveGState()
context.addPath(backgroundPath.cgPath)
context.clip()

let backgroundGradient = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [
        NSColor(calibratedRed: 0.05, green: 0.12, blue: 0.24, alpha: 1).cgColor,
        NSColor(calibratedRed: 0.05, green: 0.39, blue: 0.56, alpha: 1).cgColor,
        NSColor(calibratedRed: 0.12, green: 0.72, blue: 0.63, alpha: 1).cgColor
    ] as CFArray,
    locations: [0.0, 0.55, 1.0]
)!
context.drawLinearGradient(
    backgroundGradient,
    start: CGPoint(x: outerRect.minX, y: outerRect.maxY),
    end: CGPoint(x: outerRect.maxX, y: outerRect.minY),
    options: []
)

let glowRect = CGRect(x: 160, y: 520, width: 700, height: 420)
let glowGradient = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [
        NSColor(calibratedRed: 1, green: 1, blue: 1, alpha: 0.28).cgColor,
        NSColor(calibratedRed: 1, green: 1, blue: 1, alpha: 0.0).cgColor
    ] as CFArray,
    locations: [0.0, 1.0]
)!
context.drawRadialGradient(
    glowGradient,
    startCenter: CGPoint(x: glowRect.midX, y: glowRect.midY),
    startRadius: 0,
    endCenter: CGPoint(x: glowRect.midX, y: glowRect.midY),
    endRadius: max(glowRect.width, glowRect.height) * 0.7,
    options: []
)
context.restoreGState()

context.setStrokeColor(NSColor(calibratedWhite: 1, alpha: 0.94).cgColor)
context.setLineWidth(56)
context.setLineCap(.round)
context.setLineJoin(.round)

let shield = NSBezierPath()
shield.move(to: CGPoint(x: 512, y: 770))
shield.curve(to: CGPoint(x: 720, y: 700),
             controlPoint1: CGPoint(x: 600, y: 770),
             controlPoint2: CGPoint(x: 674, y: 742))
shield.line(to: CGPoint(x: 720, y: 504))
shield.curve(to: CGPoint(x: 512, y: 248),
             controlPoint1: CGPoint(x: 720, y: 394),
             controlPoint2: CGPoint(x: 640, y: 292))
shield.curve(to: CGPoint(x: 304, y: 504),
             controlPoint1: CGPoint(x: 384, y: 292),
             controlPoint2: CGPoint(x: 304, y: 394))
shield.line(to: CGPoint(x: 304, y: 700))
shield.curve(to: CGPoint(x: 512, y: 770),
             controlPoint1: CGPoint(x: 350, y: 742),
             controlPoint2: CGPoint(x: 424, y: 770))
shield.close()
context.addPath(shield.cgPath)
context.strokePath()

context.setStrokeColor(NSColor(calibratedWhite: 1, alpha: 0.98).cgColor)
context.setLineWidth(52)
let tunnel = CGMutablePath()
tunnel.move(to: CGPoint(x: 390, y: 610))
tunnel.addCurve(to: CGPoint(x: 516, y: 520),
                control1: CGPoint(x: 442, y: 610),
                control2: CGPoint(x: 472, y: 562))
tunnel.addCurve(to: CGPoint(x: 644, y: 420),
                control1: CGPoint(x: 560, y: 476),
                control2: CGPoint(x: 598, y: 438))
context.addPath(tunnel)
context.strokePath()

context.setFillColor(NSColor(calibratedWhite: 1, alpha: 0.98).cgColor)
context.fillEllipse(in: CGRect(x: 334, y: 582, width: 72, height: 72))
context.fillEllipse(in: CGRect(x: 608, y: 384, width: 72, height: 72))

context.setStrokeColor(NSColor(calibratedWhite: 1, alpha: 0.98).cgColor)
context.setLineWidth(40)
let arrow = CGMutablePath()
arrow.move(to: CGPoint(x: 592, y: 464))
arrow.addLine(to: CGPoint(x: 700, y: 464))
arrow.move(to: CGPoint(x: 646, y: 518))
arrow.addLine(to: CGPoint(x: 700, y: 464))
arrow.addLine(to: CGPoint(x: 646, y: 410))
context.addPath(arrow)
context.strokePath()

guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
    fputs("Could not encode PNG.\n", stderr)
    exit(1)
}

try pngData.write(to: outputURL, options: .atomic)
