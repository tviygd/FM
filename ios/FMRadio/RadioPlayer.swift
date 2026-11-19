import AVFoundation
import Combine
import MediaPlayer
import Network

@MainActor
final class RadioPlayer: ObservableObject {
    @Published private(set) var current: Station?
    @Published private(set) var isPlaying = false
    @Published private(set) var isBuffering = false
    /// The user wants audio: stays true while buffering or reconnecting, false after pause.
    @Published private(set) var wantsToPlay = false
    @Published private(set) var trackTitle = "FM Radio — слухайте онлайн"
    @Published private(set) var favorites: Set<URL> = []

    private let player = AVPlayer()
    private var metadataTask: Task<Void, Never>?
    private var timeControlObservation: NSKeyValueObservation?
    private var itemObservation: NSKeyValueObservation?
    private var itemEndObservers: [NSObjectProtocol] = []
    private var interruptionObserver: NSObjectProtocol?
    private let pathMonitor = NWPathMonitor()
    private var reconnectTask: Task<Void, Never>?
    private var stallTask: Task<Void, Never>?
    private var reconnectAttempt = 0

    private static let stallTimeout: UInt64 = 10_000_000_000
    private static let maxReconnectDelay = 15.0

    private enum Keys {
        static let lastStation = "lastStation"
        static let favorites = "favorites"
    }

    private struct Track: Decodable {
        let singer: String
        let song: String
    }

    init() {
        configureAudioSession()
        configureRemoteCommands()

        let defaults = UserDefaults.standard
        favorites = Set((defaults.stringArray(forKey: Keys.favorites) ?? []).compactMap(URL.init(string:)))
        // Autoplay on launch would be surprising, so the last station is only preselected.
        if let saved = defaults.string(forKey: Keys.lastStation),
           let station = allStations.first(where: { $0.stream.absoluteString == saved }) {
            current = station
            trackTitle = "Натисніть ▶, щоб слухати"
        }

        pathMonitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor in self?.reconnectNowIfWaiting() }
        }
        pathMonitor.start(queue: DispatchQueue(label: "FMRadio.network"))

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
        pathMonitor.cancel()
        if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
        itemEndObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    // MARK: - Controls

    func select(_ station: Station, reconnecting: Bool = false) {
        cancelReconnect()
        if !reconnecting { reconnectAttempt = 0 }
        wantsToPlay = true
        current = station
        trackTitle = reconnecting ? "Перепідключення…" : "Завантаження…"
        UserDefaults.standard.set(station.stream.absoluteString, forKey: Keys.lastStation)

        let item = AVPlayerItem(url: station.stream)
        itemObservation = item.observe(\.status) { [weak self] item, _ in
            guard item.status == .failed else { return }
            Task { @MainActor in self?.scheduleReconnect() }
        }
        itemEndObservers.forEach { NotificationCenter.default.removeObserver($0) }
        itemEndObservers = [AVPlayerItem.failedToPlayToEndTimeNotification, AVPlayerItem.didPlayToEndTimeNotification]
            .map { name in
                NotificationCenter.default.addObserver(forName: name, object: item, queue: .main) { [weak self] _ in
                    Task { @MainActor in self?.scheduleReconnect() }
                }
            }

        player.replaceCurrentItem(with: item)
        player.play()
        startMetadata()
        updateNowPlaying()
    }

    /// Cycles through favorites (or all stations if there are none), wrapping around at both ends.
    func step(by delta: Int) {
        let count = allStations.count
        guard count > 0 else { return }
        let favoriteStations = allStations.filter { favorites.contains($0.stream) }
        let pool = favoriteStations.isEmpty ? allStations : favoriteStations
        var index = current.flatMap { allStations.firstIndex(of: $0) } ?? (delta > 0 ? -1 : count)
        for _ in 0..<count {
            index = ((index + delta) % count + count) % count
            if pool.contains(allStations[index]) {
                select(allStations[index])
                return
            }
        }
    }

    func isFavorite(_ station: Station) -> Bool {
        favorites.contains(station.stream)
    }

    func toggleFavorite(_ station: Station) {
        if favorites.contains(station.stream) {
            favorites.remove(station.stream)
        } else {
            favorites.insert(station.stream)
        }
        UserDefaults.standard.set(favorites.map(\.absoluteString), forKey: Keys.favorites)
    }

    func togglePlayPause() {
        if wantsToPlay { pause() } else { resume() }
    }

    func pause() {
        wantsToPlay = false
        cancelReconnect()
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
        if isPlaying {
            stallTask?.cancel()
            stallTask = nil
            reconnectAttempt = 0
        } else if isBuffering {
            watchForStall()
        }
        updateNowPlaying()
    }

    // MARK: - Auto-reconnect

    /// Buffering that never ends (e.g. a dead connection in a tunnel) is treated as a failure.
    private func watchForStall() {
        guard wantsToPlay, stallTask == nil, reconnectTask == nil else { return }
        stallTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.stallTimeout)
            guard !Task.isCancelled, let self else { return }
            self.stallTask = nil
            if self.isBuffering { self.scheduleReconnect() }
        }
    }

    /// Retries with growing delays (2, 4, 8, 15, 15… s) until it plays again or the user pauses.
    private func scheduleReconnect() {
        guard wantsToPlay, let station = current, reconnectTask == nil else { return }
        stallTask?.cancel()
        stallTask = nil
        stopMetadata()
        let delay = min(2 * pow(2, Double(reconnectAttempt)), Self.maxReconnectDelay)
        reconnectAttempt += 1
        trackTitle = "Немає зв'язку, повтор через \(Int(delay)) с…"
        updateNowPlaying()
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            self.reconnectTask = nil
            self.select(station, reconnecting: true)
        }
    }

    private func reconnectNowIfWaiting() {
        guard reconnectTask != nil, let station = current else { return }
        select(station, reconnecting: true)
    }

    private func cancelReconnect() {
        reconnectTask?.cancel()
        reconnectTask = nil
        stallTask?.cancel()
        stallTask = nil
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
        // Steering-wheel / Bluetooth / CarPlay "next" and "previous" switch stations
        center.nextTrackCommand.isEnabled = true
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.step(by: 1) }
            return .success
        }
        center.previousTrackCommand.isEnabled = true
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.step(by: -1) }
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
