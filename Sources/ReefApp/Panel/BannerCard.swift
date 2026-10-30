import ReefCore
import SwiftUI

/// A full-width notice at the top of the panel: something needs the user's attention but is not
/// an agent request. Geometry from LAYOUT-SPEC §3.
struct BannerCard: View {
    let icon: String
    let title: String
    let message: String
    var actionLabel: String?
    var action: (() -> Void)?
    var dismiss: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(Theme.bannerIcon)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.waiting)
            }
            .frame(width: Metrics.bannerIconSize, height: Metrics.bannerIconSize)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.bodyEmphasis)
                    .foregroundStyle(Theme.textPrimary)
                Text(message)
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .lineSpacing(Metrics.textLeading - 13)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            if let actionLabel, let action {
                Button(actionLabel, action: action)
                    .buttonStyle(PanelButtonStyle(role: .secondary))
            }
            if let dismiss {
                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 19, height: 19)
                        .background(Theme.chip, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
        }
        .padding(.horizontal, Metrics.cardPadding)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: Metrics.bannerHeight, alignment: .leading)
        .background(Theme.bannerBackground, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous).stroke(Theme.bannerBorder))
    }
}
