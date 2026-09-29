import SwiftUI

/// Fades messages out as they scroll behind the header or the composer, like Telegram-iOS's chat edge effects
/// (`ChatControllerNode`'s two `WallpaperEdgeEffectNode`s). The chat background, laid over the feed, fades in on
/// Telegram's eased curve, then covers everything out to the edge: behind the status bar at the top, behind the
/// keyboard at the bottom. It goes over the feed, and under the header, the composer, the search panel and the floating
/// buttons.
struct FeedEdgeFade: View {
    let edge: VerticalEdge

    /// Fully tinted at the edge, as the owner asked, so messages are gone behind the header and below the composer.
    /// Telegram stops at 0.85 on a single-color background, which leaves them faintly visible there.
    private static let opacity = 1.0
    /// Telegram's eased curve (`EdgeEffect.generateEdgeGradient`, 90 stops), sampled: transparent at 0, full at 1, with
    /// a long faint tail.
    private static let stops: [Gradient.Stop] = [
        (0, 0), (0.21, 0.056), (0.27, 0.11), (0.30, 0.14), (0.39, 0.27), (0.45, 0.39), (0.50, 0.50),
        (0.55, 0.60), (0.61, 0.70), (0.70, 0.85), (0.78, 0.93), (0.85, 0.96), (1, 1),
    ].map { location, alpha in
        Gradient.Stop(color: Theme.background.opacity(opacity * alpha), location: location)
    }
    /// The solid part hangs past the feed's safe area out to the edge, over whatever is there.
    private static let solid: CGFloat = 2000

    /// How far into the feed the fade's transparent end reaches, from the feed's safe area. Telegram's top fade ends 34pt
    /// below the navigation bar. Its bottom one starts 20pt above the input field, which sits 4pt below the top of the
    /// composer's inset.
    private var reach: CGFloat {
        edge == .top ? 34 : 16
    }

    /// Telegram: 80pt at the top, 60pt at the bottom.
    private var length: CGFloat {
        edge == .top ? 80 : 60
    }

    var body: some View {
        VStack(spacing: 0) {
            if edge == .top {
                Theme.background.opacity(Self.opacity)
                    .frame(height: Self.solid)
                LinearGradient(stops: Self.stops, startPoint: .bottom, endPoint: .top)
                    .frame(height: length)
            } else {
                LinearGradient(stops: Self.stops, startPoint: .top, endPoint: .bottom)
                    .frame(height: length)
                Theme.background.opacity(Self.opacity)
                    .frame(height: Self.solid)
            }
        }
        // A frame `reach` tall at the edge of the feed's safe area, which is where the header or the composer's inset
        // begins. The fade's transparent end sits at its inner edge and the rest overflows outward. It moves with the
        // composer as the keyboard does.
        .frame(height: reach, alignment: edge == .top ? .bottom : .top)
        .frame(maxHeight: .infinity, alignment: edge == .top ? .top : .bottom)
        .allowsHitTesting(false)
    }
}
