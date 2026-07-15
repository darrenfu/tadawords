import SwiftUI
import TadaWordsDesignSystem

enum AppLaunchPresentationPolicy {
    static let minimumDisplayDuration = Duration.milliseconds(1_800)
    static let fadeDuration = TadaPrimitiveTokens.Motion.quick
}

/// Owns the one-shot launch sequence independently from the splash view's
/// lifetime. Production can finish remembered-profile audio configuration
/// before starting the signature and minimum display countdown, while fallback
/// routes can start the countdown immediately.
@MainActor
final class AppLaunchPresentationCoordinator: ObservableObject {
    typealias Preparation = @MainActor () async -> Void
    typealias SignaturePlayback = @MainActor () async -> Void
    typealias Sleeper = @MainActor (Duration) async throws -> Void

    @Published private(set) var isShowingLaunchPage = true

    private let sleep: Sleeper
    private var hasStarted = false
    private var sequenceTask: Task<Void, Never>?
    private var signatureTask: Task<Void, Never>?

    init(
        sleep: @escaping Sleeper = { duration in
            try await Task.sleep(for: duration)
        }
    ) {
        self.sleep = sleep
    }

    func startIfNeeded(
        prepare: @escaping Preparation = {},
        playSignature: SignaturePlayback? = nil
    ) {
        guard !hasStarted else { return }
        hasStarted = true

        sequenceTask = Task { [weak self] in
            guard let self else { return }
            await prepare()
            guard !Task.isCancelled else { return }

            if let playSignature {
                await startSignatureTask(playSignature)
            }

            do {
                try await sleep(AppLaunchPresentationPolicy.minimumDisplayDuration)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }

            withAnimation(.easeOut(duration: AppLaunchPresentationPolicy.fadeDuration)) {
                isShowingLaunchPage = false
            }
        }
    }

    private func startSignatureTask(
        _ playSignature: @escaping SignaturePlayback
    ) async {
        await withCheckedContinuation { continuation in
            signatureTask = Task {
                continuation.resume()
                await playSignature()
            }
        }
    }
}

struct AppLaunchPage: View {
    var body: some View {
        GeometryReader { proxy in
            let compactHeight = proxy.size.height < 520
            let markSize = min(
                compactHeight ? 88.0 : 120.0,
                proxy.size.height * (compactHeight ? 0.24 : 0.16)
            )

            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.965, green: 0.941, blue: 1.00),
                        Color(red: 1.00, green: 0.957, blue: 0.973),
                        Color(red: 1.00, green: 0.961, blue: 0.867),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                LaunchPageSparkles()
                    .accessibilityHidden(true)

                VStack {
                    Spacer()
                    TadaWordsLaunchMark(markSize: markSize)
                    Spacer()
                }
                .padding(.horizontal, TadaPrimitiveTokens.Spacing.xLarge)

                VStack {
                    Spacer()
                    PawgooLaunchMark(compact: compactHeight)
                        .padding(.bottom, compactHeight ? 22 : 38)
                }
                .padding(.horizontal, TadaPrimitiveTokens.Spacing.xLarge)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Tada Words by Pawgoo")
        .accessibilityIdentifier("app-launch-page")
    }
}

private struct TadaWordsLaunchMark: View {
    let markSize: CGFloat

    var body: some View {
        HStack(spacing: markSize * 0.18) {
            Image("TadaWordsMark", bundle: .main)
                .resizable()
                .scaledToFit()
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: markSize * 0.26,
                        style: .continuous
                    )
                )
                .frame(width: markSize, height: markSize)
                .shadow(
                    color: Color(red: 0.43, green: 0.29, blue: 0.82).opacity(0.22),
                    radius: 14,
                    y: 8
                )

            Text("Tada Words")
                .font(
                    .system(
                        size: markSize * 0.435,
                        weight: .black,
                        design: .rounded
                    )
                )
                .foregroundStyle(Color(red: 0.09, green: 0.13, blue: 0.24))
                .tracking(-markSize * 0.017)
                .minimumScaleFactor(0.70)
                .lineLimit(1)
        }
    }
}

private struct PawgooLaunchMark: View {
    let compact: Bool

    var body: some View {
        HStack(spacing: compact ? 7 : 9) {
            Image("PawgooMark", bundle: .main)
                .resizable()
                .scaledToFit()
                .frame(width: compact ? 24 : 32, height: compact ? 22 : 30)
                .rotationEffect(.degrees(-3))

            Text("pawgoo")
                .font(
                    .system(
                        size: compact ? 17 : 22,
                        weight: .black,
                        design: .rounded
                    )
                )
                .tracking(compact ? -0.68 : -0.88)
        }
        .foregroundStyle(Color(red: 0.09, green: 0.13, blue: 0.24))
    }
}

private struct LaunchPageSparkles: View {
    var body: some View {
        GeometryReader { proxy in
            Image(systemName: "sparkles")
                .font(.system(size: min(44, proxy.size.height * 0.10), weight: .bold))
                .foregroundStyle(TadaWorldTheme.moonpetal.secondary.opacity(0.55))
                .position(x: proxy.size.width * 0.16, y: proxy.size.height * 0.23)

            Image(systemName: "star.fill")
                .font(.system(size: min(28, proxy.size.height * 0.065), weight: .bold))
                .foregroundStyle(TadaWorldTheme.moonpetal.accent.opacity(0.58))
                .position(x: proxy.size.width * 0.85, y: proxy.size.height * 0.28)

            Circle()
                .fill(Color.white.opacity(0.32))
                .frame(width: proxy.size.height * 0.30)
                .position(x: proxy.size.width * 0.10, y: proxy.size.height * 0.88)

            Circle()
                .fill(Color(red: 0.43, green: 0.29, blue: 0.82).opacity(0.10))
                .frame(width: proxy.size.height * 0.42)
                .position(x: proxy.size.width * 0.94, y: proxy.size.height * 0.84)
        }
    }
}
