import Foundation
import RpplCore

// Compiles a Share export into the bundled empty-state example (see ExampleSessionCompiler)
// and writes it to the iPhone and Watch resource folders.
// Usage: example-session-compiler <export.json> [<repo root>]

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    FileHandle.standardError.write(Data("usage: example-session-compiler <export.json> [<repo root>]\n".utf8))
    exit(2)
}
let input = URL(fileURLWithPath: arguments[1])
let root = URL(fileURLWithPath: arguments.count > 2 ? arguments[2] : FileManager.default.currentDirectoryPath)

var package = try SessionImportLimits.decodeTransferPackage(
    from: SessionImportLimits.readBoundedFile(at: input)
)
package.manifest.activityCode = "Example session"
let compiled = ExampleSessionCompiler.compile(package)

let encoder = JSONEncoder()
encoder.dateEncodingStrategy = .iso8601
encoder.outputFormatting = [.sortedKeys]
let data = try encoder.encode(compiled) + Data("\n".utf8)

for target in ["Rppl", "RpplWatch"] {
    let directory = root.appendingPathComponent("\(target)/Resources/Exports", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let output = directory.appendingPathComponent("\(ExampleSessionPreload.resourceName).json")
    try data.write(to: output, options: [.atomic])
    print("wrote \(output.path) (\(data.count) bytes)")
}
let sets = compiled.derived?.stats.sets.count ?? 0
print("sessionId=\(package.manifest.sessionId) sets=\(sets) locations=\(compiled.locations.count)")
