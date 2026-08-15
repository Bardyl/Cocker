#!/usr/bin/env swift
//
// Génère le fond de l'image disque, dans build/dmg-background.tiff.
//
// Dessiné plutôt que stocké : le fichier reste du texte relisible en revue, et
// la version @2x sort du même code que la @1x au lieu d'être un agrandissement.
//
// La traînée de pattes remplace la flèche habituelle : elle dit la même chose —
// « fais glisser vers la droite » — en restant dans le ton de l'app, et sans
// un mot à traduire.
//
//   swift Scripts/make-dmg-background.swift
//

import AppKit
import Foundation

/// Taille de la fenêtre du DMG, en points. `Scripts/make-dmg.sh` doit annoncer
/// exactement les mêmes à create-dmg.
let windowSize = NSSize(width: 640, height: 400)

/// Où create-dmg pose les deux icônes, en partant du haut.
let appIconCenter = NSPoint(x: 170, y: 190)
let dropIconCenter = NSPoint(x: 470, y: 190)

let backgroundTop = NSColor(srgbRed: 0.11, green: 0.22, blue: 0.40, alpha: 1)
let backgroundBottom = NSColor(srgbRed: 0.05, green: 0.10, blue: 0.21, alpha: 1)
let fur = NSColor(srgbRed: 0.95, green: 0.71, blue: 0.16, alpha: 1)

func drawBackground(scale: CGFloat) -> NSImage {
    let pixels = NSSize(width: windowSize.width * scale, height: windowSize.height * scale)
    let image = NSImage(size: pixels)

    image.lockFocus()
    defer { image.unlockFocus() }

    guard let context = NSGraphicsContext.current else { return image }
    context.imageInterpolation = .high
    context.cgContext.scaleBy(x: scale, y: scale)

    let bounds = NSRect(origin: .zero, size: windowSize)
    NSGradient(starting: backgroundTop, ending: backgroundBottom)?.draw(in: bounds, angle: -90)

    drawPawTrail()
    drawWordmark()

    return image
}

/// Cinq empreintes qui montent doucement de l'app vers le dossier.
func drawPawTrail() {
    let configuration = NSImage.SymbolConfiguration(pointSize: 26, weight: .medium)
    guard let symbol = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(configuration)
    else { return }

    let count = 5
    // L'espace laissé libre entre les deux icônes, marges comprises.
    let start = appIconCenter.x + 90
    let end = dropIconCenter.x - 90

    for index in 0..<count {
        let progress = CGFloat(index) / CGFloat(count - 1)
        let x = start + (end - start) * progress

        // AppKit dessine de bas en haut : on convertit depuis le repère de
        // create-dmg, qui compte les ordonnées depuis le haut.
        let baseY = windowSize.height - appIconCenter.y
        // Une patte sur deux décalée : une trace de marche, pas un alignement.
        let y = baseY - 4 + (index.isMultiple(of: 2) ? 9 : -9)

        // Les pattes s'affirment à mesure qu'elles approchent du but.
        let opacity = 0.3 + 0.5 * progress

        let tinted = NSImage(size: symbol.size, flipped: false) { bounds in
            fur.withAlphaComponent(opacity).setFill()
            bounds.fill()
            symbol.draw(in: bounds, from: .zero, operation: .destinationIn, fraction: 1)
            return true
        }

        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: x, yBy: y)
        // Le symbole a les doigts vers le haut ; on le couche d'un quart de
        // tour pour qu'ils pointent vers le dossier Applications, comme une
        // bête qui marche vers la droite. Le léger balancement autour de cet
        // axe évite l'alignement mécanique.
        transform.rotate(byDegrees: -90 + (index.isMultiple(of: 2) ? -8 : 8))
        transform.concat()
        tinted.draw(
            in: NSRect(
                x: -tinted.size.width / 2,
                y: -tinted.size.height / 2,
                width: tinted.size.width,
                height: tinted.size.height
            )
        )
        NSGraphicsContext.restoreGraphicsState()
    }
}

/// Le nom, discret, en haut. Le seul texte de l'image — et il ne se traduit pas.
func drawWordmark() {
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 15, weight: .medium),
        .foregroundColor: NSColor.white.withAlphaComponent(0.34),
    ]
    let text = NSAttributedString(string: "Cocker", attributes: attributes)
    let size = text.size()
    text.draw(at: NSPoint(x: (windowSize.width - size.width) / 2, y: windowSize.height - 46))
}

// MARK: - Écriture

func png(from image: NSImage, size: NSSize) -> Data? {
    guard let representation = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(size.width),
        pixelsHigh: Int(size.height),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { return nil }

    representation.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: representation)
    image.draw(in: NSRect(origin: .zero, size: size))
    NSGraphicsContext.restoreGraphicsState()

    return representation.representation(using: .png, properties: [:])
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let build = root.appendingPathComponent("build")
try FileManager.default.createDirectory(at: build, withIntermediateDirectories: true)

for scale in [CGFloat(1), CGFloat(2)] {
    let size = NSSize(width: windowSize.width * scale, height: windowSize.height * scale)
    guard let data = png(from: drawBackground(scale: scale), size: size) else {
        FileHandle.standardError.write(Data("✗ rendu impossible à \(Int(scale))x\n".utf8))
        exit(1)
    }
    let name = scale == 1 ? "dmg-background.png" : "dmg-background@2x.png"
    try data.write(to: build.appendingPathComponent(name))
}

// Un TIFF multi-résolution : le Finder y choisit la version qui convient à
// l'écran. Un simple PNG @2x serait affiché deux fois trop grand.
let tiffutil = Process()
tiffutil.executableURL = URL(fileURLWithPath: "/usr/bin/tiffutil")
tiffutil.arguments = [
    "-cathidpicheck",
    build.appendingPathComponent("dmg-background.png").path,
    build.appendingPathComponent("dmg-background@2x.png").path,
    "-out",
    build.appendingPathComponent("dmg-background.tiff").path,
]
let pipe = Pipe()
tiffutil.standardOutput = pipe
tiffutil.standardError = pipe
try tiffutil.run()
tiffutil.waitUntilExit()

guard tiffutil.terminationStatus == 0 else {
    FileHandle.standardError.write(pipe.fileHandleForReading.readDataToEndOfFile())
    exit(1)
}

print("✓ \(build.appendingPathComponent("dmg-background.tiff").path)")
