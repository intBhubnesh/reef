import ReefCore
import SwiftUI

struct DiffView: View {
    let path: String?
    let lines: [DiffLine]
    var maxLines = 200

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let path {
                Text(path)
                    .font(Theme.mono.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.04))
            }
            if lines.isEmpty {
                Text("No changes")
                    .font(Theme.mono).foregroundStyle(Theme.textSecondary)
                    .padding(10)
            } else {
                ForEach(Array(lines.prefix(maxLines).enumerated()), id: \.offset) { _, line in
                    HStack(spacing: 0) {
                        Text(line.oldNumber.map(String.init) ?? "")
                            .frame(width: 34, alignment: .trailing)
                        Text(line.newNumber.map(String.init) ?? "")
                            .frame(width: 34, alignment: .trailing)
                        Text(marker(line)).frame(width: 16)
                        Text(line.text.isEmpty ? " " : line.text)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 0)
                    }
                    .font(Theme.mono)
                    .foregroundStyle(color(line))
                    .padding(.vertical, 1)
                    .background(background(line))
                }
                if lines.count > maxLines {
                    Text("… \(lines.count - maxLines) more lines")
                        .font(Theme.small).foregroundStyle(Theme.textSecondary).padding(8)
                }
            }
        }
        .background(Color.black.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func marker(_ line: DiffLine) -> String {
        switch line.kind { case .added: return "+"; case .removed: return "-"; case .context: return " " }
    }

    private func color(_ line: DiffLine) -> Color {
        switch line.kind {
        case .added: return Theme.done
        case .removed: return Theme.failed
        case .context: return Theme.textPrimary.opacity(0.8)
        }
    }

    private func background(_ line: DiffLine) -> Color {
        switch line.kind {
        case .added: return Theme.done.opacity(0.15)
        case .removed: return Theme.failed.opacity(0.15)
        case .context: return .clear
        }
    }
}
