#!/usr/bin/swift

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum OpaquePNGError: Error {
    case invalidArguments
    case unreadableImage(String)
    case cannotCreateBitmap
    case cannotCreateDestination(String)
    case cannotEncodePNG
}

guard CommandLine.arguments.count == 3 else {
    throw OpaquePNGError.invalidArguments
}

let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
let destinationURL = URL(fileURLWithPath: CommandLine.arguments[2])
guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
      let sourceImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    throw OpaquePNGError.unreadableImage(sourceURL.path)
}

let width = sourceImage.width
let height = sourceImage.height
guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
      let context = CGContext(
          data: nil,
          width: width,
          height: height,
          bitsPerComponent: 8,
          bytesPerRow: 0,
          space: colorSpace,
          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
      ) else {
    throw OpaquePNGError.cannotCreateBitmap
}

context.interpolationQuality = .high
context.draw(sourceImage, in: CGRect(x: 0, y: 0, width: width, height: height))

guard let opaqueImage = context.makeImage() else {
    throw OpaquePNGError.cannotEncodePNG
}
let temporaryURL = destinationURL
    .deletingLastPathComponent()
    .appendingPathComponent(".\(destinationURL.lastPathComponent).tmp")
guard let destination = CGImageDestinationCreateWithURL(
    temporaryURL as CFURL,
    UTType.png.identifier as CFString,
    1,
    nil
) else {
    throw OpaquePNGError.cannotCreateDestination(temporaryURL.path)
}
CGImageDestinationAddImage(destination, opaqueImage, nil)
guard CGImageDestinationFinalize(destination) else {
    throw OpaquePNGError.cannotEncodePNG
}
_ = try FileManager.default.replaceItemAt(destinationURL, withItemAt: temporaryURL)
