import Foundation
import GameApplication

// Offline stage linter. This is the layer allowed to read files: GameApplication only ever
// sees in-memory Data. Intended for CI and for authors before committing content.
//
//   swift run ContentValidator Content/stages/*.json

let paths = Array(CommandLine.arguments.dropFirst())

guard !paths.isEmpty else {
    let tool = (CommandLine.arguments.first as NSString?)?.lastPathComponent ?? "ContentValidator"
    print("usage: \(tool) <stage.json> [<stage.json> ...]")
    print("Validates SparkTread stage content and prints OK or FAIL per file.")
    exit(64) // EX_USAGE
}

var failureCount = 0

for path in paths {
    do {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        _ = try StageValidator.validate(stageData: data)
        print("OK \(path)")
    } catch let error as ContentError {
        print("FAIL \(path): \(error.description)")
        failureCount += 1
    } catch {
        // Everything else here is file access: unreadable path, permissions, bad encoding.
        print("FAIL \(path): could not read file: \(error.localizedDescription)")
        failureCount += 1
    }
}

exit(failureCount == 0 ? 0 : 1)
