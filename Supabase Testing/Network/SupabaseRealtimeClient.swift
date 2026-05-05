import Foundation

// MARK: - Configuration

public struct SupabaseRealtimeConfig {
    public let url: String
    public let apiKey: String
    public var heartbeatInterval: TimeInterval
    public var reconnectDelay: TimeInterval
    public var maxReconnectAttempts: Int

    public init(
        url: String,
        apiKey: String,
        heartbeatInterval: TimeInterval = 10.0,
        reconnectDelay: TimeInterval = 3.0,
        maxReconnectAttempts: Int = 10
    ) {
        self.url = url
        self.apiKey = apiKey
        self.heartbeatInterval = heartbeatInterval
        self.reconnectDelay = reconnectDelay
        self.maxReconnectAttempts = maxReconnectAttempts
    }
}

public enum Event: String {
    case join = "phx_join"
    case presence = "presence"
    case broadcast = "broadcast"
    case move = "move"
}

// MARK: - Connection State

public enum ConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case reconnecting(attempt: Int)

    public var isConnected: Bool { self == .connected }

    public var description: String {
        switch self {
        case .disconnected:        return "Disconnected"
        case .connecting:          return "Connecting"
        case .connected:           return "Connected"
        case .reconnecting(let n): return "Reconnecting (attempt \(n))"
        }
    }
}

// MARK: - Presence Models

public struct PresenceUser: Equatable {
    public let key: String
    public let username: String
    public let onlineAt: String
    public let phxRef: String

    public var description: String { "\(username) [\(key)]" }
}

public struct PresenceDiff {
    public let channelId: String
    public let joins: [PresenceUser]
    public let leaves: [PresenceUser]
}

// MARK: - Internal Models

private struct ChannelRegistration {
    let channelId: String
    let presenceKey: String
    let presencePayload: [String: Any]
}

/// Stored per phx_join ref so when the ack arrives we know exactly
/// which channel was confirmed and can fire the presence track immediately.
private struct PendingJoinAck {
    let channelId: String
    let registration: ChannelRegistration
}

// MARK: - Delegate

public protocol SupabaseRealtimeClientDelegate: AnyObject {
    func client(_ client: SupabaseRealtimeClient, didChangeState state: ConnectionState)
    func client(_ client: SupabaseRealtimeClient, channel: String, didReceivePresenceState users: [PresenceUser])
    func client(_ client: SupabaseRealtimeClient, didReceivePresenceDiff diff: PresenceDiff)
    func client(_ client: SupabaseRealtimeClient, didReceiveMessage message: [String: Any])
    func client(_ client: SupabaseRealtimeClient, didFailWithError error: Error)
}

// MARK: - Client

public final class SupabaseRealtimeClient: NSObject {

    // MARK: Public

    public private(set) var state: ConnectionState = .disconnected {
        didSet {
            guard state != oldValue else { return }
            log("State → \(state.description)")
            delegate?.client(self, didChangeState: state)
        }
    }

    public weak var delegate: SupabaseRealtimeClientDelegate?
    public private(set) var presenceState: [String: [PresenceUser]] = [:]

    // MARK: Private

    private let config: SupabaseRealtimeConfig
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?

    private var heartbeatTimer: Timer?
    private var globalRef: String = "0"

    private var reconnectTask: Task<Void, Never>?
    private var reconnectAttempts: Int = 0
    private var isIntentionalDisconnect: Bool = false

    /// Channels to auto-rejoin on reconnect. Only removed by leaveChannel().
    private var channelRegistry: [String: ChannelRegistration] = [:]

    /// Key = the ref used in phx_join. Removed once the ack arrives.
    private var pendingJoinAcks: [String: PendingJoinAck] = [:]

    private let queue = DispatchQueue(label: "com.supabase.realtime.client", qos: .utility)

    // MARK: Init

    public init(config: SupabaseRealtimeConfig) {
        self.config = config
    }

    // MARK: - Public: Connection

    public func connect() {
        queue.async { [weak self] in self?._connect() }
    }

    public func disconnect() {
        queue.async { [weak self] in self?._disconnect(intentional: true) }
    }

    // MARK: - Public: Channels

    public func joinChannel(
        channelId: String,
        username: String,
        extraPayload: [String: Any] = [:]
    ) {
        queue.async { [weak self] in
            guard let self else { return }

            guard self.channelRegistry[channelId] == nil else {
                self.log("[\(channelId)] Already registered — skipping duplicate join")
                return
            }

            var payload: [String: Any] = [
                "username":  username,
                "online_at": ISO8601DateFormatter().string(from: Date())
            ]
            extraPayload.forEach { payload[$0.key] = $0.value }

            let reg = ChannelRegistration(
                channelId:       channelId,
                presenceKey:     username,
                presencePayload: payload
            )

            self.channelRegistry[channelId] = reg
            self.presenceState[channelId]   = []

            if self.state.isConnected {
                self._sendJoin(reg)
            } else {
                self.log("[\(channelId)] Queued — will join once socket connects")
            }
        }
    }

    public func leaveChannel(channelId: String) {
        queue.async { [weak self] in
            guard let self else { return }

            self.channelRegistry.removeValue(forKey: channelId)
            self.presenceState.removeValue(forKey: channelId)

            // Also remove any pending join ack for this channel
            pendingJoinAcks = pendingJoinAcks.filter { $0.value.channelId != channelId }

            guard self.state.isConnected else { return }

            self._send([
                "topic":   self.topic(for: channelId),
                "event":   "phx_leave",
                "payload": [String: Any](),
                "ref":     self.nextRef()
            ])
            self.log("[\(channelId)] Left and removed from registry")
        }
    }

    // MARK: - Public: Raw Send

    public func send(_ payload: [String: Any], completion: ((Error?) -> Void)? = nil) {
        guard state.isConnected else {
            completion?(RealtimeError.notConnected)
            return
        }
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: data, encoding: .utf8) else {
            completion?(RealtimeError.serializationFailed)
            return
        }
        webSocketTask?.send(.string(text)) { error in completion?(error) }
    }

    // MARK: - Join Sequence

    /// Step 1: Send phx_join and register the ref in pendingJoinAcks.
    /// Step 2 (presence track) fires only when the server's phx_reply arrives for this ref.
    private func _sendJoin(_ reg: ChannelRegistration) {
        let joinRef = nextRef()

        // Store BEFORE sending so the ack handler can find it immediately
        pendingJoinAcks[joinRef] = PendingJoinAck(channelId: reg.channelId, registration: reg)

        _send([
            "topic":   topic(for: reg.channelId),
            "event":   Event.join.rawValue,
            "payload": [
                "config": [
                    "presence":  ["enabled": true, "key": reg.presenceKey],
                    "broadcast": ["self": true, "ack": true]
                ]
            ],
            "ref": joinRef,
            "join_ref": joinRef
        ])
        log("[\(reg.channelId)] phx_join sent (ref: \(joinRef)) — waiting for server ack")
    }

    /// Step 2: Called only after phx_reply {status:"ok"} received for the matching joinRef.
    private func _sendPresenceTrack(for reg: ChannelRegistration) {
        let trackRef = nextRef()
        _send([
            "topic":   topic(for: reg.channelId),
            "event":   Event.presence.rawValue,
            "payload": [
                "type":    "track",
                "key":     reg.presenceKey,
                "payload": reg.presencePayload
            ],
            "ref": trackRef
        ])
        log("[\(reg.channelId)] presence track sent (ref: \(trackRef))")
    }
    
    // MARK: - Public: Channels

    public func broadcastMove(
        x: String,
        y: String,
        player: String,
        channelId: String
    ) {
        queue.async { [weak self] in
            guard let self else { return }

            let trackRef = nextRef()
            let broadcast = [
                "topic":   topic(for: channelId),
                "event":   Event.broadcast.rawValue,
                "payload": [
                    "event":    Event.move.rawValue,
                    "payload": [
                        "player": player,
                        "x": x,
                        "y": y
                    ]
                ],
                "ref": trackRef
            ]

            if self.state.isConnected {
                _send(broadcast)
            } else {
                self.log("[\(channelId)] Queued — will join once socket connects")
            }
        }
    }

    /// Replays all registered channels after reconnect.
    private func _rejoinAllChannels() {
        guard !channelRegistry.isEmpty else { return }
        // Clear stale acks from the previous connection
        pendingJoinAcks.removeAll()
        log("Auto-rejoining \(channelRegistry.count) channel(s)…")
        for reg in channelRegistry.values {
            _sendJoin(reg)
        }
    }

    // MARK: - Internal Send

    private func _send(_ payload: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: data, encoding: .utf8) else { return }
        webSocketTask?.send(.string(text)) { [weak self] error in
            if let error { self?.log("Send error: \(error.localizedDescription)") }
        }
    }

    private func nextRef() -> String {
        globalRef = "\((Int(globalRef) ?? 0) + 1)"
        return globalRef
    }

    // BUG 1 FIX: no prefix added — channelId is sent exactly as provided.
    // joinChannel(channelId: "lobby") → topic "realtime:lobby"
    private func topic(for channelId: String) -> String {
        "realtime:\(channelId)"
    }

    // BUG 2 FIX: always strips exactly "realtime:" (9 chars) and nothing else.
    // "realtime:lobby" → "lobby"
    // "realtime:game-room-42" → "game-room-42"
    private func channelId(from topic: String) -> String {
        guard topic.hasPrefix("realtime:") else { return topic }
        return String(topic.dropFirst("realtime:".count))
    }

    // MARK: - Connect / Disconnect

    private func _connect() {
        guard state == .disconnected || state == .reconnecting(attempt: reconnectAttempts) else {
            log("Already \(state.description) — ignoring connect()")
            return
        }

        isIntentionalDisconnect = false
        state = .connecting

        guard let url = buildWebSocketURL() else {
            log("Invalid WebSocket URL")
            state = .disconnected
            return
        }

        let cfg = URLSessionConfiguration.ephemeral
        cfg.waitsForConnectivity       = true
        cfg.timeoutIntervalForRequest  = 30
        cfg.timeoutIntervalForResource = 60

        let session = URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
        urlSession = session

        var request = URLRequest(url: url)
        request.setValue(config.apiKey,             forHTTPHeaderField: "apikey")
//        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")

        let task = session.webSocketTask(with: request)
        webSocketTask = task
        task.resume()

        listenForMessages()
        log("WebSocket connecting → \(url.absoluteString)")
    }

    private func _disconnect(intentional: Bool) {
        isIntentionalDisconnect = intentional

        stopHeartbeat()
        reconnectTask?.cancel()
        reconnectTask     = nil
        reconnectAttempts = 0
        pendingJoinAcks.removeAll()

        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil

        presenceState = presenceState.mapValues { _ in [] }
        state = .disconnected
        log("Disconnected\(intentional ? " (intentional)" : " (unexpected)")")
    }

    // MARK: - Message Loop

    private func listenForMessages() {
        webSocketTask?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let msg):
                self.handleIncoming(msg)
                if !self.isIntentionalDisconnect { self.listenForMessages() }
            case .failure(let err):
                self.log("Receive error: \(err.localizedDescription)")
            }
        }
    }

    private func handleIncoming(_ message: URLSessionWebSocketTask.Message) {
        var text: String?
        switch message {
        case .string(let s): text = s
        case .data(let d):   text = String(data: d, encoding: .utf8)
        @unknown default:    break
        }

        guard let raw  = text,
              let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            log("Could not parse incoming message")
            return
        }

        let event     = json["event"]   as? String ?? ""
        let topic     = json["topic"]   as? String ?? ""
        let payload   = json["payload"] as? [String: Any] ?? [:]
        let ref       = json["ref"]     as? String ?? ""

        // BUG 2 FIX: use dedicated helper that always strips exactly "realtime:"
        let channelId = self.channelId(from: topic)

        log("◀ event=\(event) channel=\(channelId) ref=\(ref)")

        switch event {

        case "phx_reply":
            guard topic != "phoenix" else {
                log("Heartbeat ack ✓")
                return
            }

            let status = payload["status"] as? String ?? ""

            // BUG 3 FIX: presence track fires here — only after confirmed join ack.
            // We match the reply ref to the stored pendingJoinAcks entry.
            if let pending = pendingJoinAcks.removeValue(forKey: ref) {
                if status == "ok" {
                    log("[\(pending.channelId)] Join confirmed ✓ — sending presence track now")
                    _sendPresenceTrack(for: pending.registration)
                } else {
                    log("[\(pending.channelId)] Join failed — status: \(status)")
                }
            }

        case "presence_state":
            queue.async { [weak self] in
                self?.handlePresenceState(channelId: channelId, raw: payload)
            }

        case "presence_diff":
            queue.async { [weak self] in
                self?.handlePresenceDiff(channelId: channelId, raw: payload)
            }

        default:
            delegate?.client(self, didReceiveMessage: json)
        }
    }

    // MARK: - Presence Handlers

    private func handlePresenceState(channelId: String, raw: [String: Any]) {
        let users = parsePresenceMap(raw)
        presenceState[channelId] = users

        let names = users.map(\.description).joined(separator: ", ")
        log("[\(channelId)] presence_state → [\(names.isEmpty ? "empty" : names)]")

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.client(self, channel: channelId, didReceivePresenceState: users)
        }
    }

    private func handlePresenceDiff(channelId: String, raw: [String: Any]) {
        let joins  = parsePresenceMap(raw["joins"]  as? [String: Any] ?? [:])
        let leaves = parsePresenceMap(raw["leaves"] as? [String: Any] ?? [:])

        var current = presenceState[channelId] ?? []
        let leaveRefs = Set(leaves.map(\.phxRef))
        current.removeAll { leaveRefs.contains($0.phxRef) }

        let existingRefs = Set(current.map(\.phxRef))
        current.append(contentsOf: joins.filter { !existingRefs.contains($0.phxRef) })
        presenceState[channelId] = current

        if !joins.isEmpty  { log("[\(channelId)] +joined: \(joins.map(\.description).joined(separator: ", "))") }
        if !leaves.isEmpty { log("[\(channelId)] -left:   \(leaves.map(\.description).joined(separator: ", "))") }

        let diff = PresenceDiff(channelId: channelId, joins: joins, leaves: leaves)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.client(self, didReceivePresenceDiff: diff)
        }
    }

    private func parsePresenceMap(_ map: [String: Any]) -> [PresenceUser] {
        map.compactMap { key, value -> PresenceUser? in
            guard let entry = value as? [String: Any],
                  let metas = entry["metas"] as? [[String: Any]],
                  let meta  = metas.first else { return nil }
            return PresenceUser(
                key:      key,
                username: meta["username"]  as? String ?? key,
                onlineAt: meta["online_at"] as? String ?? "",
                phxRef:   meta["phx_ref"]   as? String ?? ""
            )
        }
    }

    // MARK: - Heartbeat

    private func startHeartbeat() {
        stopHeartbeat()
        log("Heartbeat started (every \(config.heartbeatInterval)s)")
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.heartbeatTimer = Timer.scheduledTimer(
                withTimeInterval: self.config.heartbeatInterval,
                repeats: true
            ) { [weak self] _ in
                self?.sendHeartbeat()
            }
        }
    }

    private func stopHeartbeat() {
        DispatchQueue.main.async { [weak self] in
            self?.heartbeatTimer?.invalidate()
            self?.heartbeatTimer = nil
        }
    }

    private func sendHeartbeat() {
        let ref = nextRef()
        queue.async { [weak self] in
            guard let self, self.state.isConnected else { return }
            self._send([
                "topic":   "phoenix",
                "event":   "heartbeat",
                "payload": [String: Any](),
                "ref":     ref
            ])
            self.log("Heartbeat sent (ref: \(ref))")
        }
    }

    // MARK: - Reconnect

    private func scheduleReconnect() {
        guard !isIntentionalDisconnect else { return }
        guard reconnectAttempts < config.maxReconnectAttempts else {
            log("Max reconnect attempts reached — giving up")
            state = .disconnected
            return
        }

        reconnectAttempts += 1
        state = .reconnecting(attempt: reconnectAttempts)

        let delay = config.reconnectDelay * Double(reconnectAttempts)
        log("Will reconnect in \(delay)s (attempt \(reconnectAttempts)/\(config.maxReconnectAttempts))")

        reconnectTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self.queue.async { self._connect() }
        }
    }

    // MARK: - URL

    private func buildWebSocketURL() -> URL? {
        var base = config.url
            .replacingOccurrences(of: "https://", with: "wss://")
            .replacingOccurrences(of: "http://",  with: "ws://")
        if base.hasSuffix("/") { base = String(base.dropLast()) }
        var urlString = "\(base)/realtime/v1/websocket?apikey=\(config.apiKey)&vsn=1.0.0"//
        if let jwtToken = UserDefaults.standard.string(forKey: "access_token") {
            urlString += "&\(jwtToken)"
        }
        return URL(string: urlString)
    }

    // MARK: - Log

    private func log(_ message: String) {
        print("[SupabaseRealtime] \(message)")
    }
}

// MARK: - URLSessionWebSocketDelegate

extension SupabaseRealtimeClient: URLSessionWebSocketDelegate {

    public func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        queue.async { [weak self] in
            guard let self else { return }
            self.reconnectAttempts = 0
            self.state = .connected
            self.startHeartbeat()
            self._rejoinAllChannels()
        }
    }

    public func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        let r = reason.flatMap { String(data: $0, encoding: .utf8) } ?? "none"
        log("Socket closed — code: \(closeCode.rawValue), reason: \(r)")
        queue.async { [weak self] in
            guard let self else { return }
            self.stopHeartbeat()
            self.isIntentionalDisconnect ? (self.state = .disconnected) : self.scheduleReconnect()
        }
    }

    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let error else { return }
        log("Task error: \(error.localizedDescription)")
        queue.async { [weak self] in
            guard let self else { return }
            self.stopHeartbeat()
            self.delegate?.client(self, didFailWithError: error)
            self.isIntentionalDisconnect ? (self.state = .disconnected) : self.scheduleReconnect()
        }
    }
}

// MARK: - Errors

public enum RealtimeError: LocalizedError {
    case notConnected
    case serializationFailed

    public var errorDescription: String? {
        switch self {
        case .notConnected:        return "WebSocket is not connected."
        case .serializationFailed: return "Failed to serialize message payload."
        }
    }
}
