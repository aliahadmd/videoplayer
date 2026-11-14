// SPDX-License-Identifier: GPL-3.0-or-later
//
// LiPlayer — Native macOS video player built with Swift, AppKit, SwiftUI, and libmpv.
// Copyright (C) 2026 Ali Ahad <https://aliahad.com>
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. If not, see <https://www.gnu.org/licenses/>.

import AppKit
import Foundation

// Generates macOS AppIcon.iconset, optional document iconset, and brand logo assets for LiPlayer.

func squirclePath(rect: NSRect, radius: CGFloat) -> CGPath {
    // Smooth macOS continuous-curvature squircle.
    let path = CGMutablePath()
    let minX = rect.minX, maxX = rect.maxX
    let minY = rect.minY, maxY = rect.maxY
    let r = min(radius, min(rect.width, rect.height) * 0.45)
    let ext = min(r * 1.22, min(rect.width, rect.height) * 0.48)
    let c = ext * 0.31 // handle length = 0.69 * ext for smooth macOS continuous corner

    path.move(to: CGPoint(x: minX + ext, y: minY))
    path.addLine(to: CGPoint(x: maxX - ext, y: minY))
    path.addCurve(
        to: CGPoint(x: maxX, y: minY + ext),
        control1: CGPoint(x: maxX - c, y: minY),
        control2: CGPoint(x: maxX, y: minY + c)
    )
    path.addLine(to: CGPoint(x: maxX, y: maxY - ext))
    path.addCurve(
        to: CGPoint(x: maxX - ext, y: maxY),
        control1: CGPoint(x: maxX, y: maxY - c),
        control2: CGPoint(x: maxX - c, y: maxY)
    )
    path.addLine(to: CGPoint(x: minX + ext, y: maxY))
    path.addCurve(
        to: CGPoint(x: minX, y: maxY - ext),
        control1: CGPoint(x: minX + c, y: maxY),
        control2: CGPoint(x: minX, y: maxY - c)
    )
    path.addLine(to: CGPoint(x: minX, y: minY + ext))
    path.addCurve(
        to: CGPoint(x: minX + ext, y: minY),
        control1: CGPoint(x: minX, y: minY + c),
        control2: CGPoint(x: minX + c, y: minY)
    )
    path.closeSubpath()
    return path
}

func roundedPolygonPath(points: [CGPoint], cornerRadius: CGFloat) -> CGPath {
    let path = CGMutablePath()
    guard points.count >= 3 else { return path }
    for i in 0..<points.count {
        let prev = points[(i - 1 + points.count) % points.count]
        let curr = points[i]
        let next = points[(i + 1) % points.count]
        let v1 = CGVector(dx: prev.x - curr.x, dy: prev.y - curr.y)
        let v2 = CGVector(dx: next.x - curr.x, dy: next.y - curr.y)
        let len1 = hypot(v1.dx, v1.dy)
        let len2 = hypot(v2.dx, v2.dy)
        let d = min(cornerRadius, min(len1, len2) * 0.42)
        let p1 = CGPoint(x: curr.x + v1.dx / len1 * d, y: curr.y + v1.dy / len1 * d)
        let p2 = CGPoint(x: curr.x + v2.dx / len2 * d, y: curr.y + v2.dy / len2 * d)
        if i == 0 {
            path.move(to: p1)
        } else {
            path.addLine(to: p1)
        }
        path.addQuadCurve(to: p2, control: curr)
    }
    path.closeSubpath()
    return path
}

func drawGradient(_ ctx: CGContext, colors: [NSColor], locations: [CGFloat], start: CGPoint, end: CGPoint) {
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let cgColors = colors.map { $0.usingColorSpace(.sRGB)!.cgColor } as CFArray
    if let grad = CGGradient(colorsSpace: cs, colors: cgColors, locations: locations) {
        ctx.drawLinearGradient(grad, start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }
}

func drawRadialGradient(_ ctx: CGContext, colors: [NSColor], locations: [CGFloat], center: CGPoint, radius: CGFloat) {
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let cgColors = colors.map { $0.usingColorSpace(.sRGB)!.cgColor } as CFArray
    if let grad = CGGradient(colorsSpace: cs, colors: cgColors, locations: locations) {
        ctx.drawRadialGradient(grad, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [.drawsAfterEndLocation])
    }
}

func lLetterPath() -> CGPath {
    // L monogram with smooth inner fillet and rounded corners, spanning x: 236..364, y: 356..668
    let p = CGMutablePath()
    let left: CGFloat = 236
    let rightStem: CGFloat = 294
    let rightFoot: CGFloat = 366
    let bottom: CGFloat = 356
    let topFoot: CGFloat = 414
    let topStem: CGFloat = 668
    let r: CGFloat = 18
    let innerR: CGFloat = 14

    p.move(to: CGPoint(x: left + r, y: bottom))
    p.addLine(to: CGPoint(x: rightFoot - r, y: bottom))
    p.addQuadCurve(to: CGPoint(x: rightFoot, y: bottom + r), control: CGPoint(x: rightFoot, y: bottom))
    p.addLine(to: CGPoint(x: rightFoot, y: topFoot - r))
    p.addQuadCurve(to: CGPoint(x: rightFoot - r, y: topFoot), control: CGPoint(x: rightFoot, y: topFoot))
    p.addLine(to: CGPoint(x: rightStem + innerR, y: topFoot))
    p.addQuadCurve(to: CGPoint(x: rightStem, y: topFoot + innerR), control: CGPoint(x: rightStem, y: topFoot))
    p.addLine(to: CGPoint(x: rightStem, y: topStem - r))
    p.addQuadCurve(to: CGPoint(x: rightStem - r, y: topStem), control: CGPoint(x: rightStem, y: topStem))
    p.addLine(to: CGPoint(x: left + r, y: topStem))
    p.addQuadCurve(to: CGPoint(x: left, y: topStem - r), control: CGPoint(x: left, y: topStem))
    p.addLine(to: CGPoint(x: left, y: bottom + r))
    p.addQuadCurve(to: CGPoint(x: left + r, y: bottom), control: CGPoint(x: left, y: bottom))
    p.closeSubpath()
    return p
}

func renderLiPlayerIcon(pixels: Int, includeShadow: Bool = true) -> NSBitmapImageRep {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .calibratedRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let nsCtx = NSGraphicsContext(bitmapImageRep: bitmap) else {
        fatalError("Could not create icon bitmap")
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = nsCtx
    let ctx = nsCtx.cgContext
    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high
    ctx.scaleBy(x: CGFloat(pixels) / 1024.0, y: CGFloat(pixels) / 1024.0)

    let squircleRect = NSRect(x: 100, y: 100, width: 824, height: 824)
    let squircle = squirclePath(rect: squircleRect, radius: 184)

    // 1. Soft grounding shadow for macOS icon canvas
    if includeShadow && pixels >= 64 {
        ctx.saveGState()
        ctx.setShadow(
            offset: CGSize(width: 0, height: -14),
            blur: 26,
            color: NSColor(calibratedWhite: 0, alpha: 0.48).cgColor
        )
        ctx.addPath(squircle)
        ctx.setFillColor(NSColor(calibratedRed: 0.04, green: 0.05, blue: 0.08, alpha: 1).cgColor)
        ctx.fillPath()
        ctx.restoreGState()
    }

    // 2. Obsidian glass body + ambient prism glow
    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.clip()

    drawGradient(
        ctx,
        colors: [
            NSColor(srgbRed: 0.105, green: 0.133, blue: 0.195, alpha: 1),
            NSColor(srgbRed: 0.051, green: 0.067, blue: 0.106, alpha: 1),
            NSColor(srgbRed: 0.027, green: 0.035, blue: 0.059, alpha: 1)
        ],
        locations: [0, 0.52, 1],
        start: CGPoint(x: 140, y: 900),
        end: CGPoint(x: 880, y: 120)
    )

    // Atmospheric cyan/cobalt glow behind the play prism
    drawRadialGradient(
        ctx,
        colors: [
            NSColor(srgbRed: 0.055, green: 0.647, blue: 0.914, alpha: 0.34),
            NSColor(srgbRed: 0.145, green: 0.388, blue: 0.922, alpha: 0.14),
            NSColor(srgbRed: 0.05, green: 0.08, blue: 0.16, alpha: 0)
        ],
        locations: [0, 0.45, 1],
        center: CGPoint(x: 610, y: 512),
        radius: 440
    )

    // Subtle secondary glow behind the 'i' cyan orb
    drawRadialGradient(
        ctx,
        colors: [
            NSColor(srgbRed: 0.220, green: 0.741, blue: 0.973, alpha: 0.20),
            NSColor(srgbRed: 0.220, green: 0.741, blue: 0.973, alpha: 0)
        ],
        locations: [0, 1],
        center: CGPoint(x: 416, y: 638),
        radius: 175
    )

    // Top studio glass reflection arc
    ctx.saveGState()
    let sheen = CGMutablePath()
    sheen.move(to: CGPoint(x: 100, y: 924))
    sheen.addLine(to: CGPoint(x: 924, y: 924))
    sheen.addLine(to: CGPoint(x: 924, y: 630))
    sheen.addQuadCurve(to: CGPoint(x: 100, y: 540), control: CGPoint(x: 520, y: 690))
    sheen.closeSubpath()
    ctx.addPath(sheen)
    ctx.clip()
    drawGradient(
        ctx,
        colors: [
            NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.075),
            NSColor(srgbRed: 0.75, green: 0.90, blue: 1, alpha: 0.015),
            NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0)
        ],
        locations: [0, 0.5, 1],
        start: CGPoint(x: 512, y: 924),
        end: CGPoint(x: 512, y: 540)
    )
    ctx.restoreGState()

    // Crisp inner glass rim highlight
    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.setLineWidth(pixels <= 32 ? 16 : 6)
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    drawGradient(
        ctx,
        colors: [
            NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.30),
            NSColor(srgbRed: 0.38, green: 0.80, blue: 0.98, alpha: 0.16),
            NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.05)
        ],
        locations: [0, 0.45, 1],
        start: CGPoint(x: 160, y: 900),
        end: CGPoint(x: 880, y: 120)
    )
    ctx.restoreGState()

    // 3. Monogram "Li"
    // 'L' pillar + foot
    let lPath = lLetterPath()
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 16, color: NSColor(calibratedWhite: 0, alpha: 0.45).cgColor)
    ctx.addPath(lPath)
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(lPath)
    ctx.clip()
    drawGradient(
        ctx,
        colors: [
            NSColor(srgbRed: 0.99, green: 0.995, blue: 1.0, alpha: 1),
            NSColor(srgbRed: 0.90, green: 0.935, blue: 0.975, alpha: 1),
            NSColor(srgbRed: 0.72, green: 0.79, blue: 0.88, alpha: 1)
        ],
        locations: [0, 0.55, 1],
        start: CGPoint(x: 280, y: 668),
        end: CGPoint(x: 320, y: 356)
    )
    ctx.restoreGState()

    // 'i' stem
    let iStemRect = CGRect(x: 388, y: 356, width: 56, height: 214)
    let iStemPath = CGPath(roundedRect: iStemRect, cornerWidth: 20, cornerHeight: 20, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 16, color: NSColor(calibratedWhite: 0, alpha: 0.45).cgColor)
    ctx.addPath(iStemPath)
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(iStemPath)
    ctx.clip()
    drawGradient(
        ctx,
        colors: [
            NSColor(srgbRed: 0.98, green: 0.995, blue: 1.0, alpha: 1),
            NSColor(srgbRed: 0.88, green: 0.925, blue: 0.97, alpha: 1),
            NSColor(srgbRed: 0.72, green: 0.79, blue: 0.88, alpha: 1)
        ],
        locations: [0, 0.55, 1],
        start: CGPoint(x: 416, y: 570),
        end: CGPoint(x: 416, y: 356)
    )
    ctx.restoreGState()

    // 'i' luminous cyan lens orb
    let dotRect = CGRect(x: 385, y: 606, width: 62, height: 62)
    let dotPath = CGPath(ellipseIn: dotRect, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 0), blur: 20, color: NSColor(srgbRed: 0.22, green: 0.76, blue: 0.98, alpha: 0.75).cgColor)
    ctx.addPath(dotPath)
    ctx.setFillColor(NSColor(srgbRed: 0.22, green: 0.76, blue: 0.98, alpha: 1).cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(dotPath)
    ctx.clip()
    drawGradient(
        ctx,
        colors: [
            NSColor(srgbRed: 0.75, green: 0.95, blue: 1.0, alpha: 1),
            NSColor(srgbRed: 0.14, green: 0.72, blue: 0.98, alpha: 1),
            NSColor(srgbRed: 0.12, green: 0.36, blue: 0.90, alpha: 1)
        ],
        locations: [0, 0.45, 1],
        start: CGPoint(x: 398, y: 668),
        end: CGPoint(x: 438, y: 606)
    )
    ctx.restoreGState()

    // 4. Luminous Blue/Cyan Play Prism
    let prismPoints = [
        CGPoint(x: 492, y: 682),
        CGPoint(x: 786, y: 512),
        CGPoint(x: 492, y: 342)
    ]
    let prismPath = roundedPolygonPath(points: prismPoints, cornerRadius: 42)

    // Back-prism outer glow
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -4), blur: 34, color: NSColor(srgbRed: 0.06, green: 0.65, blue: 0.95, alpha: 0.65).cgColor)
    ctx.addPath(prismPath)
    ctx.setFillColor(NSColor(srgbRed: 0.12, green: 0.56, blue: 0.96, alpha: 1).cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    // Prism core gradient
    ctx.saveGState()
    ctx.addPath(prismPath)
    ctx.clip()

    drawGradient(
        ctx,
        colors: [
            NSColor(srgbRed: 0.490, green: 0.875, blue: 0.996, alpha: 1), // bright cyan ice
            NSColor(srgbRed: 0.055, green: 0.647, blue: 0.935, alpha: 1), // electric cyan
            NSColor(srgbRed: 0.145, green: 0.388, blue: 0.922, alpha: 1), // cobalt blue
            NSColor(srgbRed: 0.285, green: 0.245, blue: 0.840, alpha: 1)  // deep indigo accent
        ],
        locations: [0, 0.34, 0.72, 1],
        start: CGPoint(x: 492, y: 682),
        end: CGPoint(x: 786, y: 352)
    )

    // Upper internal glass refraction facet
    ctx.saveGState()
    let upperFacet = CGMutablePath()
    upperFacet.move(to: CGPoint(x: 480, y: 690))
    upperFacet.addLine(to: CGPoint(x: 796, y: 512))
    upperFacet.addLine(to: CGPoint(x: 480, y: 500))
    upperFacet.closeSubpath()
    ctx.addPath(upperFacet)
    ctx.clip()
    drawGradient(
        ctx,
        colors: [
            NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.36),
            NSColor(srgbRed: 0.75, green: 0.95, blue: 1, alpha: 0.10),
            NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0)
        ],
        locations: [0, 0.5, 1],
        start: CGPoint(x: 520, y: 682),
        end: CGPoint(x: 680, y: 505)
    )
    ctx.restoreGState()

    // Crisp prism internal specular edge highlight
    ctx.saveGState()
    ctx.addPath(prismPath)
    ctx.setLineWidth(pixels <= 32 ? 12 : 6)
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    drawGradient(
        ctx,
        colors: [
            NSColor(srgbRed: 0.92, green: 0.98, blue: 1.0, alpha: 0.92),
            NSColor(srgbRed: 0.45, green: 0.88, blue: 1.0, alpha: 0.55),
            NSColor(srgbRed: 0.55, green: 0.65, blue: 1.0, alpha: 0.25)
        ],
        locations: [0, 0.5, 1],
        start: CGPoint(x: 492, y: 682),
        end: CGPoint(x: 786, y: 342)
    )
    ctx.restoreGState()

    ctx.restoreGState() // end prism clip
    ctx.restoreGState() // end squircle clip

    NSGraphicsContext.restoreGraphicsState()
    return bitmap
}

func renderQueueDocIcon(pixels: Int) -> NSBitmapImageRep {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .calibratedRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let nsCtx = NSGraphicsContext(bitmapImageRep: bitmap) else {
        fatalError("Could not create doc icon bitmap")
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = nsCtx
    let ctx = nsCtx.cgContext
    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)
    ctx.scaleBy(x: CGFloat(pixels) / 1024.0, y: CGFloat(pixels) / 1024.0)

    // macOS folded-corner dark document page
    let page = CGMutablePath()
    let left: CGFloat = 176, right: CGFloat = 848
    let bottom: CGFloat = 86, top: CGFloat = 938
    let fold: CGFloat = 176
    let r: CGFloat = 46

    page.move(to: CGPoint(x: left + r, y: bottom))
    page.addLine(to: CGPoint(x: right - r, y: bottom))
    page.addQuadCurve(to: CGPoint(x: right, y: bottom + r), control: CGPoint(x: right, y: bottom))
    page.addLine(to: CGPoint(x: right, y: top - fold))
    page.addLine(to: CGPoint(x: right - fold, y: top))
    page.addLine(to: CGPoint(x: left + r, y: top))
    page.addQuadCurve(to: CGPoint(x: left, y: top - r), control: CGPoint(x: left, y: top))
    page.addLine(to: CGPoint(x: left, y: bottom + r))
    page.addQuadCurve(to: CGPoint(x: left + r, y: bottom), control: CGPoint(x: left, y: bottom))
    page.closeSubpath()

    if pixels >= 64 {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 24, color: NSColor(calibratedWhite: 0, alpha: 0.42).cgColor)
        ctx.addPath(page)
        ctx.setFillColor(NSColor(calibratedWhite: 0.08, alpha: 1).cgColor)
        ctx.fillPath()
        ctx.restoreGState()
    }

    ctx.saveGState()
    ctx.addPath(page)
    ctx.clip()
    drawGradient(
        ctx,
        colors: [
            NSColor(srgbRed: 0.13, green: 0.16, blue: 0.23, alpha: 1),
            NSColor(srgbRed: 0.06, green: 0.08, blue: 0.13, alpha: 1)
        ],
        locations: [0, 1],
        start: CGPoint(x: 200, y: 938),
        end: CGPoint(x: 820, y: 86)
    )

    // Subtle queue list bars at bottom
    for (idx, width) in [(0, CGFloat(390)), (1, CGFloat(310)), (2, CGFloat(350))] {
        let y = 240 - CGFloat(idx) * 44
        let bar = CGPath(roundedRect: CGRect(x: 317, y: y, width: width, height: 18), cornerWidth: 9, cornerHeight: 9, transform: nil)
        ctx.addPath(bar)
        ctx.setFillColor(NSColor(srgbRed: 0.65, green: 0.76, blue: 0.90, alpha: idx == 0 ? 0.50 : 0.26).cgColor)
        ctx.fillPath()
    }

    // Center play prism badge
    let prism = roundedPolygonPath(points: [
        CGPoint(x: 416, y: 690),
        CGPoint(x: 660, y: 550),
        CGPoint(x: 416, y: 410)
    ], cornerRadius: 30)
    ctx.saveGState()
    ctx.addPath(prism)
    ctx.clip()
    drawGradient(
        ctx,
        colors: [
            NSColor(srgbRed: 0.45, green: 0.87, blue: 1.0, alpha: 1),
            NSColor(srgbRed: 0.08, green: 0.52, blue: 0.94, alpha: 1),
            NSColor(srgbRed: 0.25, green: 0.28, blue: 0.86, alpha: 1)
        ],
        locations: [0, 0.5, 1],
        start: CGPoint(x: 416, y: 690),
        end: CGPoint(x: 660, y: 410)
    )
    ctx.restoreGState()

    // Page fold corner
    let corner = CGMutablePath()
    let foldInset: CGFloat = 26
    corner.move(to: CGPoint(x: right - fold, y: top))
    corner.addLine(to: CGPoint(x: right - fold, y: top - fold + foldInset))
    corner.addQuadCurve(to: CGPoint(x: right - fold + foldInset, y: top - fold), control: CGPoint(x: right - fold, y: top - fold))
    corner.addLine(to: CGPoint(x: right, y: top - fold))
    corner.closeSubpath()
    ctx.addPath(corner)
    ctx.setFillColor(NSColor(srgbRed: 0.24, green: 0.30, blue: 0.40, alpha: 0.95).cgColor)
    ctx.fillPath()

    ctx.restoreGState()

    // Subtle page border
    ctx.addPath(page)
    ctx.setStrokeColor(NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.16).cgColor)
    ctx.setLineWidth(4)
    ctx.strokePath()

    NSGraphicsContext.restoreGraphicsState()
    return bitmap
}

func writePNG(_ bitmap: NSBitmapImageRep, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try bitmap.representation(using: .png, properties: [:])!.write(to: url)
}

func brandSVG() -> String {
    """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024" role="img" aria-label="LiPlayer Logo">
      <defs>
        <linearGradient id="bg" x1="14%" y1="12%" x2="86%" y2="88%">
          <stop offset="0%" stop-color="#1B2232"/>
          <stop offset="52%" stop-color="#0D111B"/>
          <stop offset="100%" stop-color="#07090F"/>
        </linearGradient>
        <radialGradient id="prismGlow" cx="60%" cy="50%" r="44%">
          <stop offset="0%" stop-color="#0EA5E9" stop-opacity="0.34"/>
          <stop offset="48%" stop-color="#2563EB" stop-opacity="0.14"/>
          <stop offset="100%" stop-color="#0D1428" stop-opacity="0"/>
        </radialGradient>
        <linearGradient id="rim" x1="16%" y1="12%" x2="86%" y2="88%">
          <stop offset="0%" stop-color="#FFFFFF" stop-opacity="0.30"/>
          <stop offset="45%" stop-color="#61CCFA" stop-opacity="0.16"/>
          <stop offset="100%" stop-color="#FFFFFF" stop-opacity="0.05"/>
        </linearGradient>
        <linearGradient id="letterGrad" x1="0%" y1="0%" x2="10%" y2="100%">
          <stop offset="0%" stop-color="#FCFDFF"/>
          <stop offset="55%" stop-color="#E6EEF9"/>
          <stop offset="100%" stop-color="#B8C9E0"/>
        </linearGradient>
        <linearGradient id="dotGrad" x1="20%" y1="0%" x2="80%" y2="100%">
          <stop offset="0%" stop-color="#BFF2FF"/>
          <stop offset="45%" stop-color="#24B8FA"/>
          <stop offset="100%" stop-color="#1F5CE6"/>
        </linearGradient>
        <linearGradient id="prismGrad" x1="0%" y1="0%" x2="100%" y2="100%">
          <stop offset="0%" stop-color="#7DDFFF"/>
          <stop offset="34%" stop-color="#0EA5EF"/>
          <stop offset="72%" stop-color="#2563EB"/>
          <stop offset="100%" stop-color="#493FD6"/>
        </linearGradient>
        <linearGradient id="facetGrad" x1="20%" y1="0%" x2="65%" y2="100%">
          <stop offset="0%" stop-color="#FFFFFF" stop-opacity="0.36"/>
          <stop offset="50%" stop-color="#BFF2FF" stop-opacity="0.10"/>
          <stop offset="100%" stop-color="#FFFFFF" stop-opacity="0"/>
        </linearGradient>
        <filter id="dropShadow" x="-15%" y="-15%" width="130%" height="130%">
          <feDropShadow dx="0" dy="14" stdDeviation="16" flood-color="#000000" flood-opacity="0.45"/>
        </filter>
        <filter id="prismBloom" x="-25%" y="-25%" width="150%" height="150%">
          <feDropShadow dx="0" dy="4" stdDeviation="18" flood-color="#0FA6F2" flood-opacity="0.55"/>
        </filter>
      </defs>
      <g filter="url(#dropShadow)">
        <rect x="100" y="100" width="824" height="824" rx="188" fill="url(#bg)"/>
        <rect x="100" y="100" width="824" height="824" rx="188" fill="url(#prismGlow)"/>
        <rect x="103" y="103" width="818" height="818" rx="185" fill="none" stroke="url(#rim)" stroke-width="6"/>
      </g>
      <path d="M 254 356 H 276 Q 294 356 294 374 V 596 Q 294 610 308 610 H 348 Q 366 610 366 628 V 650 Q 366 668 348 668 H 254 Q 236 668 236 650 V 374 Q 236 356 254 356 Z" fill="url(#letterGrad)"/>
      <rect x="388" y="454" width="56" height="214" rx="20" fill="url(#letterGrad)"/>
      <circle cx="416" cy="387" r="31" fill="url(#dotGrad)"/>
      <g filter="url(#prismBloom)">
        <path d="M 492 378 Q 492 342 524 360 L 754 494 Q 786 512 754 530 L 524 664 Q 492 682 492 646 Z" fill="url(#prismGrad)"/>
        <path d="M 492 378 Q 492 342 524 360 L 754 494 Q 772 504 756 512 L 492 524 Z" fill="url(#facetGrad)"/>
      </g>
    </svg>
    """
}

let args = Array(CommandLine.arguments.dropFirst())
guard let first = args.first else {
    fputs("Usage: make-icon.swift <app-iconset-dir> [--doc-iconset <dir>] [--brand-dir <dir>]\n", stderr)
    exit(1)
}

let appIconset = URL(fileURLWithPath: first)
try FileManager.default.createDirectory(at: appIconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try writePNG(renderLiPlayerIcon(pixels: pixels), to: appIconset.appendingPathComponent(name))
    }
}

if let docIndex = args.firstIndex(of: "--doc-iconset"), docIndex + 1 < args.count {
    let docIconset = URL(fileURLWithPath: args[docIndex + 1])
    try FileManager.default.createDirectory(at: docIconset, withIntermediateDirectories: true)
    for points in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            let pixels = points * scale
            let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
            try writePNG(renderQueueDocIcon(pixels: pixels), to: docIconset.appendingPathComponent(name))
        }
    }
}

if let brandIndex = args.firstIndex(of: "--brand-dir"), brandIndex + 1 < args.count {
    let brandDir = URL(fileURLWithPath: args[brandIndex + 1])
    try FileManager.default.createDirectory(at: brandDir, withIntermediateDirectories: true)
    try writePNG(renderLiPlayerIcon(pixels: 1024), to: brandDir.appendingPathComponent("LiPlayer-Logo.png"))
    try writePNG(renderLiPlayerIcon(pixels: 512), to: brandDir.appendingPathComponent("LiPlayer-Logo-512.png"))
    try brandSVG().write(to: brandDir.appendingPathComponent("LiPlayer-Mark.svg"), atomically: true, encoding: .utf8)
}
