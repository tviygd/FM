import MediaPlayer
import SwiftUI

private extension Color {
    static let appBackground = Color(red: 0x0d / 255, green: 0x0d / 255, blue: 0x1a / 255)
    static let accent = Color(red: 0x7c / 255, green: 0x6f / 255, blue: 0xf7 / 255)
    static let accentLight = Color(red: 0xa8 / 255, green: 0x9f / 255, blue: 1)
}

struct ContentView: View {
    @EnvironmentObject private var player: RadioPlayer

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            VStack(spacing: 16) {
                PlayerCard()
                    .padding(.horizontal, 16)

                List {
                    ForEach(stationGroups) { group in
                        Section {
                            ForEach(group.stations) { station in
                                StationRow(station: station, isActive: player.current == station)
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
            }
            .padding(.top, 8)
        }
    }
}

private struct StationRow: View {
    let station: Station
    let isActive: Bool

    var body: some View {
        HStack {
            Text(station.name)
                .font(.system(size: 15, weight: isActive ? .medium : .regular))
                .foregroundStyle(isActive ? Color.accentLight : .white.opacity(0.6))
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 9))
                .foregroundStyle(isActive ? Color.accent : .white.opacity(0.3))
        }
        .padding(.vertical, 6)
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
                    Text(player.current == nil ? "ОБЕРІТЬ СТАНЦІЮ" : "ЗАРАЗ ГРАЄ")
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
                Button {
                    player.togglePlayPause()
                } label: {
                    ZStack {
                        Circle()
                            .fill(player.current == nil ? Color.white.opacity(0.1) : Color.accent)
                            .shadow(color: Color.accent.opacity(player.current == nil ? 0 : 0.4), radius: 9, y: 4)
                        if player.isBuffering {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(width: 52, height: 52)
                }
                .disabled(player.current == nil)
                .accessibilityLabel(player.isPlaying ? "Пауза" : "Відтворити")

                SystemVolumeSlider()
                    .frame(height: 34)
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
