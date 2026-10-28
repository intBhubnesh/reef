import Foundation
import ReefCore

let stdin = FileHandle.standardInput.readDataToEndOfFile()
let code = BridgeCLI.run(arguments: Array(CommandLine.arguments.dropFirst()), stdin: stdin,
                         env: ProcessInfo.processInfo.environment) { FileHandle.standardOutput.write($0) }
exit(code)
