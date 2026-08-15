#!/usr/bin/env swift
//
// Génère Resources/Cocker.icns.
//
// Le dessin est vectoriel et paramétré par la taille : chaque résolution est
// rendue à sa taille réelle plutôt qu'agrandie depuis un seul rendu, sinon le
// museau devient une bouillie à 16 px.
//
//   swift Scripts/make-icon.swift
//

import AppKit
import Foundation

// MARK: - Palette

/// Bleu nuit : l'héritage Docker, qu'on garde pour dire de quoi l'app parle.
let backgroundTop = NSColor(srgbRed: 0.11, green: 0.22, blue: 0.40, alpha: 1)
let backgroundBottom = NSColor(srgbRed: 0.05, green: 0.10, blue: 0.21, alpha: 1)
/// Doré : la robe du cocker, et ce qui distingue l'icône de Docker.
let fur = NSColor(srgbRed: 0.95, green: 0.71, blue: 0.16, alpha: 1)
let crateFill = NSColor(srgbRed: 0.18, green: 0.33, blue: 0.58, alpha: 1)
let crateEdge = NSColor(srgbRed: 0.29, green: 0.49, blue: 0.79, alpha: 1)

// MARK: - Dessin

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    defer { image.unlockFocus() }

    guard let context = NSGraphicsContext.current else { return image }
    context.imageInterpolation = .high

    // macOS réserve une marge autour du contenu : une icône à bord perdu
    // paraît plus grosse que toutes ses voisines dans le Dock.
    let inset = size * 0.09
    let plate = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let corner = plate.width * 0.2237

    let plateShape = NSBezierPath(roundedRect: plate, xRadius: corner, yRadius: corner)
    plateShape.addClip()

    NSGradient(starting: backgroundTop, ending: backgroundBottom)?
        .draw(in: plate, angle: -90)

    drawCrate(in: plate)
    drawMuzzle(in: plate)

    return image
}

/// La caisse de conteneur, posée en bas.
func drawCrate(in plate: NSRect) {
    let width = plate.width * 0.64
    let height = plate.height * 0.24
    let crate = NSRect(
        x: plate.midX - width / 2,
        y: plate.minY + plate.height * 0.12,
        width: width,
        height: height
    )
    let radius = height * 0.16

    let body = NSBezierPath(roundedRect: crate, xRadius: radius, yRadius: radius)
    crateFill.setFill()
    body.fill()

    // Les lattes : trois traits, assez épais pour survivre à 32 px.
    crateEdge.setStroke()
    let lineWidth = max(1, height * 0.075)
    for index in 1...2 {
        let x = crate.minX + crate.width * CGFloat(index) / 3
        let slat = NSBezierPath()
        slat.move(to: NSPoint(x: x, y: crate.minY + height * 0.22))
        slat.line(to: NSPoint(x: x, y: crate.maxY - height * 0.22))
        slat.lineWidth = lineWidth
        slat.lineCapStyle = .round
        slat.stroke()
    }

    // Arête supérieure, pour que la caisse ne soit pas un simple rectangle.
    let lid = NSBezierPath()
    lid.move(to: NSPoint(x: crate.minX + radius, y: crate.maxY - lineWidth / 2))
    lid.line(to: NSPoint(x: crate.maxX - radius, y: crate.maxY - lineWidth / 2))
    lid.lineWidth = lineWidth
    lid.lineCapStyle = .round
    crateEdge.setStroke()
    lid.stroke()
}

/// Le museau, en appui sur le haut de la caisse.
func drawMuzzle(in plate: NSRect) {
    let configuration = NSImage.SymbolConfiguration(
        pointSize: plate.height * 0.52,
        weight: .medium
    )
    guard let symbol = NSImage(systemSymbolName: "dog.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(configuration)
    else { return }

    let tinted = NSImage(size: symbol.size, flipped: false) { bounds in
        fur.setFill()
        bounds.fill()
        symbol.draw(in: bounds, from: .zero, operation: .destinationIn, fraction: 1)
        return true
    }

    let target = NSRect(
        x: plate.midX - tinted.size.width / 2,
        y: plate.minY + plate.height * 0.29,
        width: tinted.size.width,
        height: tinted.size.height
    )
    tinted.draw(in: target)
}

// MARK: - Écriture

func png(from image: NSImage, pixels: Int) -> Data? {
    guard let representation = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { return nil }

    representation.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: representation)
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()

    return representation.representation(using: .png, properties: [:])
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = root.appendingPathComponent("build/Cocker.iconset")
let output = root.appendingPathComponent("Resources/Cocker.icns")

try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
try FileManager.default.createDirectory(
    at: output.deletingLastPathComponent(),
    withIntermediateDirectories: true
)

/// (taille logique, facteur) — la nomenclature attendue par `iconutil`.
let variants: [(Int, Int)] = [
    (16, 1), (16, 2),
    (32, 1), (32, 2),
    (128, 1), (128, 2),
    (256, 1), (256, 2),
    (512, 1), (512, 2),
]

for (points, scale) in variants {
    let pixels = points * scale
    let image = drawIcon(size: CGFloat(pixels))
    guard let data = png(from: image, pixels: pixels) else {
        FileHandle.standardError.write(Data("✗ rendu impossible en \(pixels) px\n".utf8))
        exit(1)
    }
    let suffix = scale == 1 ? "" : "@2x"
    let name = "icon_\(points)x\(points)\(suffix).png"
    try data.write(to: iconset.appendingPathComponent(name))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["--convert", "icns", iconset.path, "--output", output.path]
try iconutil.run()
iconutil.waitUntilExit()

guard iconutil.terminationStatus == 0 else {
    FileHandle.standardError.write(Data("✗ iconutil a échoué\n".utf8))
    exit(1)
}

try? FileManager.default.removeItem(at: iconset)
print("✓ \(output.path)")
