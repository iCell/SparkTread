import Foundation
import ContentValidatorKit

// Usage: content-validator <content-root>   (defaults to ./Content)
let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Content")
let issues = RegistryLoader.validateContentRoot(root)
if issues.isEmpty {
    print("Content validation passed: \(root.path)")
    exit(0)
}
for issue in issues {
    print("error: \(issue)")
}
print("\(issues.count) content issue(s).")
exit(1)
