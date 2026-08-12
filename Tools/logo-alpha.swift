// Одноразовый инструмент: из логотипа-плашки на белом делает два PNG с
// прозрачным фоном — тёмная краска для светлых страниц и светлая для тёмных.
//
// Идея: на белом листе непрозрачность краски = 255 - яркость. Серые пиксели
// (текст, волна, дуга) переводятся в альфу, красные (сам рубин) остаются
// цветом. Плашка и её тень уходят вместе с фоном.
//
// swift logo-alpha.swift <in.png> <out-light.png> <out-dark.png>

import AppKit
import Foundation

let args = CommandLine.arguments
guard args.count == 4,
    let source = NSImage(contentsOfFile: args[1]),
    let cg = source.cgImage(forProposedRect: nil, context: nil, hints: nil)
else {
    print("usage: swift logo-alpha.swift <in.png> <out-light.png> <out-dark.png>")
    exit(2)
}

let width = cg.width
let height = cg.height
var pixels = [UInt8](repeating: 0, count: width * height * 4)
guard
    let context = CGContext(
        data: &pixels, width: width, height: height, bitsPerComponent: 8,
        bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
else { exit(2) }
context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))

func makeInk(light: Bool) -> [UInt8] {
    var out = [UInt8](repeating: 0, count: pixels.count)
    for index in stride(from: 0, to: pixels.count, by: 4) {
        let r = Int(pixels[index]), g = Int(pixels[index + 1]), b = Int(pixels[index + 2])
        let maxC = max(r, g, b), minC = min(r, g, b)
        let saturation = maxC - minC
        // Красный уклон ловит и бледные блики граней рубина: по насыщенности
        // они почти серые, но это камень, а не краска. Без этого на тёмном
        // фоне в рубине выгорали чёрные пятна.
        let redBias = r - max(g, b)
        if saturation > 40 || redBias > 8 {
            // Цветное — рубин и красная кнопка. Оставляем как есть.
            out[index] = UInt8(r)
            out[index + 1] = UInt8(g)
            out[index + 2] = UInt8(b)
            out[index + 3] = 255
            continue
        }
        // Серое: яркость становится плотностью краски.
        let luma = (r * 299 + g * 587 + b * 114) / 1000
        // Порог 240, а не 255: плашка и её мягкая тень чуть темнее белого, и
        // на тёмном фоне они проступали светлым квадратом вокруг знака.
        let alpha = min(255, max(0, 240 - luma) * 255 / 240)
        let tone: UInt8 = light ? 26 : 240
        // Premultiplied alpha: цвет уже умножен на альфу.
        let premultiplied = UInt8(Int(tone) * alpha / 255)
        out[index] = premultiplied
        out[index + 1] = premultiplied
        out[index + 2] = premultiplied
        out[index + 3] = UInt8(alpha)
    }
    return out
}

/// Фон — только то, что связано с краем картинки. Всё остальное со слабой
/// альфой заперто внутри знака: это блики граней рубина, почти белые и потому
/// принятые за фон. Их возвращаем цветом, иначе на тёмной странице сквозь
/// камень просвечивает страница (чёрные прорехи по граням).
func repairEnclosedHighlights(_ data: inout [UInt8]) {
    var visited = [Bool](repeating: false, count: width * height)
    var stack: [Int] = []
    func push(_ x: Int, _ y: Int) {
        guard x >= 0, y >= 0, x < width, y < height else { return }
        let index = y * width + x
        guard !visited[index], data[index * 4 + 3] < 60 else { return }
        visited[index] = true
        stack.append(index)
    }
    for x in 0..<width { push(x, 0); push(x, height - 1) }
    for y in 0..<height { push(0, y); push(width - 1, y) }
    while let index = stack.popLast() {
        // Обход идёт по слабой краске (порог 60), но стираем только дымку
        // плашки и тени. Волна местами не гуще 40 — она часть знака, не фон.
        if data[index * 4 + 3] < 14 {
            data[index * 4] = 0
            data[index * 4 + 1] = 0
            data[index * 4 + 2] = 0
            data[index * 4 + 3] = 0
        }
        let x = index % width, y = index / width
        push(x - 1, y); push(x + 1, y); push(x, y - 1); push(x, y + 1)
    }
    // Запертые области бывают двух родов: блики внутри рубина и «дырки» букв
    // (внутренность R, P, B). Возвращаем только те, что граничат с цветом, —
    // иначе внутри букв появляются белые заплаты.
    func isColor(_ index: Int) -> Bool {
        let r = Int(pixels[index * 4]), g = Int(pixels[index * 4 + 1]),
            b = Int(pixels[index * 4 + 2])
        return max(r, g, b) - min(r, g, b) > 40 || r - max(g, b) > 8
    }
    var seen = [Bool](repeating: false, count: width * height)
    for start in 0..<(width * height)
    where !visited[start] && !seen[start]
        && data[start * 4 + 3] < 60
    {
        var component: [Int] = []
        var touchesColor = false
        var queue = [start]
        seen[start] = true
        while let index = queue.popLast() {
            component.append(index)
            let x = index % width, y = index / width
            for (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)] {
                guard nx >= 0, ny >= 0, nx < width, ny < height else { continue }
                let neighbour = ny * width + nx
                if data[neighbour * 4 + 3] < 60 {
                    if !seen[neighbour] {
                        seen[neighbour] = true
                        queue.append(neighbour)
                    }
                } else if isColor(neighbour) {
                    touchesColor = true
                }
            }
        }
        guard touchesColor else { continue }
        for index in component {
            data[index * 4] = pixels[index * 4]
            data[index * 4 + 1] = pixels[index * 4 + 1]
            data[index * 4 + 2] = pixels[index * 4 + 2]
            data[index * 4 + 3] = 255
        }
    }
}

/// Обрезка по содержимому: после снятия плашки поля занимают половину картинки.
func contentBox(_ data: [UInt8], threshold: UInt8 = 12) -> CGRect {
    var minX = width, minY = height, maxX = 0, maxY = 0
    for y in 0..<height {
        for x in 0..<width where data[(y * width + x) * 4 + 3] > threshold {
            minX = min(minX, x)
            maxX = max(maxX, x)
            minY = min(minY, y)
            maxY = max(maxY, y)
        }
    }
    guard minX <= maxX else { return CGRect(x: 0, y: 0, width: width, height: height) }
    return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
}

func write(_ data: [UInt8], crop: CGRect, to path: String) {
    var buffer = data
    guard
        let ctx = CGContext(
            data: &buffer, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
        let image = ctx.makeImage()?.cropping(to: crop)
    else { exit(2) }
    let rep = NSBitmapImageRep(cgImage: image)
    rep.size = NSSize(width: image.width, height: image.height)
    guard let png = rep.representation(using: .png, properties: [:]) else { exit(2) }
    try? png.write(to: URL(fileURLWithPath: path))
    print("\(path): \(image.width)×\(image.height)")
}

var lightInk = makeInk(light: true)
var darkInk = makeInk(light: false)
repairEnclosedHighlights(&lightInk)
repairEnclosedHighlights(&darkInk)
// Одна и та же рамка для обоих файлов — иначе версии «прыгают» при смене темы.
let box = contentBox(lightInk)
write(lightInk, crop: box, to: args[2])
write(darkInk, crop: box, to: args[3])
