import AVFoundation
import Combine
import MediaPlayer

@MainActor
final class RadioPlayer: ObservableObject {
    @Published private(set) var current: Station?
    @Published private(set) var isPlaying = false
    @Published private(set) var isBuffering = false
    @Published private(set) var trackTitle = "FM Radio — слухайте онлайн"

    private let player = AVPlayer()
    private var metadataTask: Task<Void, Never>?
    private var timeControlObservation: NSKeyValueObservation?
    private var itemObservation: NSKeyValueObservation?
    private var interruptionObserver: NSObjectProtocol?

    private struct Track: Decodable {
        let singer: String
        let song: String
    }

    init() {
        configureAudioSession()
        configureRemoteCommands()

        timeControlObservation = player.observe(\.timeControlStatus) { [weak self] player, _ in
            let status = player.timeControlStatus
            Task { @MainActor in self?.handle(timeControlStatus: status) }
        }

        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let optionsRaw = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt
            Task { @MainActor in self?.handleInterruption(typeRaw: raw, optionsRaw: optionsRaw) }
        }
    }

    deinit {
        if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
    }

    // MARK: - Controls

    func select(_ station: Station) {
        current = station
        trackTitle = "Завантаження…"

        let item = AVPlayerItem(url: station.stream)
        itemObservation = item.observe(\.status) { [weak self] item, _ in
            guard item.status == .failed else { return }
            Task { @MainActor in self?.handleFailure() }
        }
        player.replaceCurrentItem(with: item)
        player.play()
        startMetadata()
        updateNowPlaying()
    }

    func togglePlayPause() {
        if isPlaying || isBuffering { pause() } else { resume() }
    }

    func pause() {
        player.pause()
        stopMetadata()
        trackTitle = "Призупинено"
        updateNowPlaying()
    }

    func resume() {
        // A live stream must be re-opened, otherwise old buffered audio plays first.
        guard let station = current else { return }
        select(station)
    }

    // MARK: - State

    private func handle(timeControlStatus status: AVPlayer.TimeControlStatus) {
        isPlaying = status == .playing
        isBuffering = status == .waitingToPlayAtSpecifiedRate
        updateNowPlaying()
    }

    private func handleFailure() {
        stopMetadata()
        trackTitle = "Помилка підключення"
        isPlaying = false
        isBuffering = false
    }

    private func handleInterruption(typeRaw: UInt?, optionsRaw: UInt?) {
        guard let typeRaw, let type = AVAudioSession.InterruptionType(rawValue: typeRaw) else { return }
        switch type {
        case .began:
            pause()
        case .ended:
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsRaw ?? 0)
            if options.contains(.shouldResume) { resume() }
        @unknown default:
            break
        }
    }

    // MARK: - Metadata

    private func startMetadata() {
        stopMetadata()
        guard let url = current?.metadata else { return }
        metadataTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.fetchMetadata(from: url)
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }

    private func stopMetadata() {
        metadataTask?.cancel()
        metadataTask = nil
    }

    private func fetchMetadata(from url: URL) async {
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let first = try JSONDecoder().decode([Track].self, from: data).first,
                  !Task.isCancelled,
                  current?.metadata == url
            else { return }
            trackTitle = Self.decodeHTML("\(first.singer) — \(first.song)")
            updateNowPlaying()
        } catch {
            // Network or decoding errors are ignored; the next poll retries.
        }
    }

    private static func decodeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#039;", with: "'")
            .replacingOccurrences(of: "<br\\s*/?>", with: " ", options: [.regularExpression, .caseInsensitive])
    }

    // MARK: - System integration

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)
    }

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.resume() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlayPause() }
            return .success
        }
    }

    private func updateNowPlaying() {
        guard let station = current else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: trackTitle,
            MPMediaItemPropertyArtist: station.name,
            MPNowPlayingInfoPropertyIsLiveStream: true,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
    }
}
