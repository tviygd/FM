import MediaPlayer
import SwiftUI

private extension Color {
    static let appBackground = Color(red: 0x0d / 255, green: 0x0d / 255, blue: 0x1a / 255)
    static let accent = Color(red: 0x7c / 255, green: 0x6f / 255, blue: 0xf7 / 255)
    static let accentLight = Color(red: 0xa8 / 255, green: 0x9f / 255, blue: 1)
    static let favorite = Color(red: 0xf5 / 255, green: 0xc4 / 255, blue: 0x51 / 255)
}

struct ContentView: View {
    @EnvironmentObject private var player: RadioPlayer

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            VStack(spacing: 16) {
                PlayerCard()
                    .padding(.horizontal, 16)

                ScrollViewReader { proxy in
                    List {
                        ForEach(stationGroups) { group in
                            Section {
                                ForEach(group.stations) { station in
                                    StationRow(
                                        station: station,
                                        isActive: player.current == station,
                                        isFavorite: player.isFavorite(station),
                                        onToggleFavorite: { player.toggleFavorite(station) }
                                    )
                                        .id(station.id)
                                        .contentShape(Rectangle())
                                        .onTapGesture { player.select(station) }
                                        .listRowBackground(
                                            RoundedRectangle(cornerRadius: 12)
                                                .fill(player.current == station ? Color.accent.opacity(0.18) : .clear)
                                                .padding(.vertical, 1)
                                        )
                                        .listRowSeparator(.hidden)
                                }
                            } header: {
                                Text(group.title.uppercased())
                                    .font(.system(size: 10, weight: .semibold))
                                    .tracking(1)
                                    .foregroundStyle(.white.opacity(0.3))
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .onChange(of: player.current) { station in
                        guard let station else { return }
                        withAnimation { proxy.scrollTo(station.id) }
                    }
                }
            }
            .padding(.top, 8)
        }
    }
}

private struct StationRow: View {
    let station: Station
    let isActive: Bool
    let isFavorite: Bool
    let onToggleFavorite: () -> Void

    var body: some View {
        HStack {
            Text(station.name)
                .font(.system(size: 15, weight: isActive ? .medium : .regular))
                .foregroundStyle(isActive ? Color.accentLight : .white.opacity(0.6))
            Spacer()
            Button(action: onToggleFavorite) {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .font(.system(size: 14))
                    .foregroundStyle(isFavorite ? Color.favorite : .white.opacity(0.3))
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            // Borderless keeps the tap on the star from also selecting the row
            .buttonStyle(.borderless)
            .accessibilityLabel(isFavorite ? "Прибрати з обраного" : "Додати в обране")
        }
        .padding(.vertical, 2)
    }
}

private struct PlayerCard: View {
    @EnvironmentObject private var player: RadioPlayer

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    Circle()
                        .fill(player.isPlaying ? Color.accentLight : .white.opacity(0.3))
                        .frame(width: 6, height: 6)
                    Text(player.current == nil ? "ОБЕРІТЬ СТАНЦІЮ" : player.wantsToPlay ? "ЗАРАЗ ГРАЄ" : "ОСТАННЯ СТАНЦІЯ")
                        .font(.system(size: 11, weight: .medium))
                        .tracking(1.2)
                        .foregroundStyle(Color.accentLight)
                }

                Text(player.current?.name ?? " ")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.3))

                HStack(alignment: .center, spacing: 10) {
                    Text(player.trackTitle)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    EqualizerView(isActive: player.isPlaying)
                }
                .frame(minHeight: 48)
            }

            HStack(spacing: 14) {
                NavButton(systemName: "backward.fill", label: "Попередня станція") { player.step(by: -1) }

                Button {
                    player.togglePlayPause()
                } label: {
                    ZStack {
                        Circle()
                            .fill(player.current == nil ? Color.white.opacity(0.1) : Color.accent)
                            .shadow(color: Color.accent.opacity(player.current == nil ? 0 : 0.4), radius: 9, y: 4)
                        // Spinner while buffering or waiting to reconnect; a tap still pauses
                        if player.wantsToPlay && !player.isPlaying {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: player.wantsToPlay ? "pause.fill" : "play.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(width: 52, height: 52)
                }
                .disabled(player.current == nil)
                .accessibilityLabel(player.wantsToPlay ? "Пауза" : "Відтворити")

                NavButton(systemName: "forward.fill", label: "Наступна станція") { player.step(by: 1) }

                SystemVolumeSlider()
                    .frame(height: 34)
            }

            let favoriteCount = allStations.filter(player.isFavorite).count
            if favoriteCount > 0 {
                Text("⏮ ⏭ перемикають лише обрані станції (\(favoriteCount))")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.3))
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(.white.opacity(0.05))
                .overlay(RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.08)))
        )
    }
}

private struct NavButton: View {
    let systemName: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 40, height: 40)
                .contentShape(Circle())
        }
        .accessibilityLabel(label)
    }
}

private struct EqualizerView: View {
    let isActive: Bool
    private let heights: [CGFloat] = [8, 16, 10, 20]

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.05, paused: !isActive)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(heights.indices, id: \.self) { i in
                    let scale = isActive ? 0.25 + 0.75 * abs(sin(t * 3.5 + Double(i) * 0.9)) : 0.25
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.accent)
                        .frame(width: 3, height: heights[i] * scale)
                }
            }
            .frame(height: 22, alignment: .bottom)
        }
    }
}

/// System volume slider. On iOS apps cannot set the volume themselves,
/// MPVolumeView controls the device volume (it is not shown in the Simulator).
private struct SystemVolumeSlider: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(frame: .zero)
        view.tintColor = UIColor(red: 0x7c / 255, green: 0x6f / 255, blue: 0xf7 / 255, alpha: 1)
        return view
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}
