#!/usr/bin/env swift

import Foundation

struct IconBuildError: LocalizedError {
    let message: String

    var errorDescription: String? {
        message
    }
}

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    throw IconBuildError(message: "usage: build-app-icon.swift <input.png> <output.png>")
}

let inputURL = URL(fileURLWithPath: arguments[1])
let outputURL = URL(fileURLWithPath: arguments[2])
let outputDirectory = outputURL.deletingLastPathComponent()

guard FileManager.default.fileExists(atPath: inputURL.path) else {
    throw IconBuildError(message: "Unable to read icon source: \(inputURL.path)")
}

try FileManager.default.createDirectory(
    at: outputDirectory,
    withIntermediateDirectories: true
)
if FileManager.default.fileExists(atPath: outputURL.path) {
    try FileManager.default.removeItem(at: outputURL)
}
try FileManager.default.copyItem(at: inputURL, to: outputURL)
