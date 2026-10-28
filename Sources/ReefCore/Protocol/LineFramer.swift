import Foundation

/// Splits a byte stream into newline-terminated lines, buffering partial trailing data.
public final class LineFramer {
    private var buffer = Data()

    public init() {}

    public func append(_ data: Data) -> [Data] {
        buffer.append(data)
        var lines: [Data] = []
        while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            lines.append(buffer.subdata(in: buffer.startIndex..<newline))
            buffer.removeSubrange(buffer.startIndex...newline)
        }
        return lines
    }
}
