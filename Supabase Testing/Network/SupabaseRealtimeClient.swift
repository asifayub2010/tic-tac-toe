//
//  SupabaseRealtimeConfig.swift
//  Supabase Testing
//
//  Created by mac on 07/05/2026.
//


import Foundation
import Network
import Starscream

// MARK: - Configuration

public struct SupabaseRealtimeConfig {
    public let url: String
    public let apiKey: String
    public var heartbeatInterval: TimeInterval
    public var reconnectDelay: TimeInterval
    public var maxReconnectAttempts: Int
    public var connectionTimeout: TimeInterval

    public init(
        url: String,
        apiKey: String,
        heartbeatInterval: TimeInterval = 15.0,
        reconnectDelay: TimeInterval = 1.0,
        maxReconnectAttempts: Int = Int.max,
        connectionTimeout: TimeInterval = 30.0
    ) {
        self.url = url
        self.apiKey = apiKey
        self.heartbeatInterval = heartbeatInterval
        self.reconnectDelay = reconnectDelay
        self.maxReconnectAttempts = maxReconnectAttempts
        self.connectionTimeout = connectionTimeout
    }
}

// MARK: - Events

public enum RealtimeEvent: String {
    case join      = "phx_join"
    case leave     = "phx_leave"
    case reply     = "phx_reply"
    case heartbeat = "heartbeat"
    case presence  = "presence"
    case broadcast = "broadcast"
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
    let presencePayload: [String: Any]   // clean user metadata only
}

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

public final class SupabaseRealtimeClient {

    // MARK: - Public

    public private(set) var state: ConnectionState = .disconnected {
        didSet {
            guard state != oldValue else { return }
            log("State → \(state.description)")
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.delegate?.client(self, didChangeState: state)
            }
        }
    }

    public weak var delegate: SupabaseRealtimeClientDelegate?
    public private(set) var presenceState: [String: [PresenceUser]] = [:]

    // MARK: - Private

    private let config: SupabaseRealtimeConfig
    private var socket: Starscream.WebSocket?

    // Starscream uses its own internal background queue so all callbacks
    // arrive off-main — we serialize our own state on a dedicated queue.
    private let queue = DispatchQueue(label: "com.supabase.realtime.client", qos: .userInitiated)

    private var globalRef: Int = 0
    private var heartbeatTimer: DispatchSourceTimer?   // DispatchSource — no main-thread dependency
    private var missedHeartbeats: Int = 0
    private let maxMissedHeartbeats = 3

    private var reconnectTask: Task<Void, Never>?
    private var reconnectAttempts: Int = 0
    private var isIntentionalDisconnect: Bool = false
    // Guards against the double-reconnect bug (listenForMessages + didCompleteWithError)
    private var isReconnectScheduled: Bool = false

    private var channelRegistry: [String: ChannelRegistration] = [:]
    private var pendingJoinAcks: [String: PendingJoinAck] = [:]

    private var networkMonitor: NWPathMonitor?
    private var isNetworkAvailable: Bool = true

    // MARK: - Init

    public init(config: SupabaseRealtimeConfig) {
        self.config = config
        setupNetworkMonitor()
    }

    deinit {
        networkMonitor?.cancel()
        _disconnect(intentional: true)
    }

    // MARK: - Public API: Connection

    public func connect() {
        queue.async { [weak self] in self?._connect() }
    }

    public func disconnect() {
        queue.async { [weak self] in self?._disconnect(intentional: true) }
    }

    // MARK: - Public API: Channels

    /// Join a channel and track presence.
    /// Safe to call before connect() — queued and replayed on connect.
    public func joinChannel(
        channelId: String,
        username: String,
        extraPayload: [String: Any] = [:]
    ) {
        queue.async { [weak self] in
            guard let self else { return }

            guard channelRegistry[channelId] == nil else {
                log("[\(channelId)] Already registered — skipping duplicate join")
                return
            }
            
            let payload: [String: Any] = [
                "username":  username,
                "online_at": ISO8601DateFormatter().string(from: Date())
            ]
            // FIX: presencePayload contains ONLY user metadata (username, online_at, extras).
            // The track envelope (type, key) is added in _sendPresenceTrack — not here.
            var userMeta: [String: Any] = [
                "type": "presence",
                "event": "track",
                "payload": payload
            ]
            extraPayload.forEach { userMeta[$0.key] = $0.value }

            let reg = ChannelRegistration(
                channelId:       channelId,
                presenceKey:     username,
                presencePayload: userMeta
            )

            channelRegistry[channelId] = reg
            presenceState[channelId]   = []

            if state.isConnected {
                _sendJoin(reg)
            } else {
                log("[\(channelId)] Queued — will join once socket connects")
            }
        }
    }

    /// Leave a channel permanently. Will not rejoin on reconnect.
    public func leaveChannel(channelId: String) {
        queue.async { [weak self] in
            guard let self else { return }

            channelRegistry.removeValue(forKey: channelId)
            presenceState.removeValue(forKey: channelId)
            pendingJoinAcks = pendingJoinAcks.filter { $0.value.channelId != channelId }

            guard state.isConnected else { return }

            _send([
                "topic":   topic(for: channelId),
                "event":   RealtimeEvent.leave.rawValue,
                "payload": [String: Any](),
                "ref":     nextRef()
            ])
            log("[\(channelId)] Left and removed from registry")
        }
    }

    // MARK: - Public API: Broadcast

    /// Broadcast any custom event to a channel.
    public func broadcast(channelId: String, event: String, payload: [String: Any]) {
        queue.async { [weak self] in
            guard let self else { return }
            guard state.isConnected else {
                log("[\(channelId)] Cannot broadcast — not connected")
                return
            }
            _send([
                "topic":   topic(for: channelId),
                "event":   RealtimeEvent.broadcast.rawValue,
                "payload": [
                    "type":    "broadcast",
                    "event":   event,
                    "payload": payload
                ],
                "ref": nextRef()
            ])
        }
    }

    /// Broadcast a player move (convenience wrapper).
    public func broadcastMove(channelId: String, player: String, x: String, y: String) {
        broadcast(channelId: channelId, event: "move", payload: [
            "player": player,
            "x": x,
            "y": y
        ])
    }

    /// Send a raw payload. For advanced use.
    public func send(_ payload: [String: Any], completion: ((Error?) -> Void)? = nil) {
        queue.async { [weak self] in
            guard let self else {
                completion?(RealtimeError.notConnected)
                return
            }
            guard state.isConnected else {
                completion?(RealtimeError.notConnected)
                return
            }
            _send(payload)
            completion?(nil)
        }
    }

    // MARK: - Join Sequence

    /// Step 1: send phx_join, register ref in pendingJoinAcks.
    private func _sendJoin(_ reg: ChannelRegistration) {
        let joinRef = nextRef()
        // Store BEFORE sending so the ack is never missed
        pendingJoinAcks[joinRef] = PendingJoinAck(channelId: reg.channelId, registration: reg)

        _send([
            "topic":    topic(for: reg.channelId),
            "event":    RealtimeEvent.join.rawValue,
            "payload":  [
                "config": [
                    "presence":  ["key": reg.presenceKey],
                    "broadcast": ["self": true, "ack": false]
                ]
            ],
            "ref":      joinRef,
            "join_ref": joinRef
        ])
        log("[\(reg.channelId)] phx_join sent (ref: \(joinRef))")
    }

    /// Step 2: send presence track — called ONLY after phx_reply {ok} for the join ref.
    /// FIX: envelope (type, key) is here; presencePayload contains only user metadata.
    private func _sendPresenceTrack(for reg: ChannelRegistration) {
        let trackRef = nextRef()
        _send([
            "topic":   topic(for: reg.channelId),
            "event":   RealtimeEvent.presence.rawValue,
            "payload": reg.presencePayload,
//                [
//                "type":    "track",
//                "key":     reg.presenceKey,
//                "payload": reg.presencePayload      // {username, online_at, ...extras}
//            ],
            "ref": trackRef
        ])
        log("[\(reg.channelId)] presence track sent (ref: \(trackRef))")
    }

    /// Replays all channels after every reconnect.
    private func _rejoinAllChannels() {
        guard !channelRegistry.isEmpty else { return }
        pendingJoinAcks.removeAll()
        log("Auto-rejoining \(channelRegistry.count) channel(s)…")
        for reg in channelRegistry.values { _sendJoin(reg) }
    }

    // MARK: - Low-Level Send

    private func _send(_ payload: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: data, encoding: .utf8) else {
            log("Serialization failed: \(payload)")
            return
        }
        // Starscream's write() is thread-safe
        socket?.write(string: text)
    }

    private func nextRef() -> String {
        globalRef += 1
        return "\(globalRef)"
    }

    private func topic(for channelId: String) -> String {
        "realtime:\(channelId)"
    }

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

        guard isNetworkAvailable else {
            log("No network — will connect when network returns")
            return
        }

        isIntentionalDisconnect  = false
        isReconnectScheduled     = false
        state = .connecting

        guard let url = buildWebSocketURL() else {
            log("Invalid WebSocket URL")
            state = .disconnected
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = config.connectionTimeout
        request.setValue(config.apiKey,             forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("websocket",               forHTTPHeaderField: "Upgrade")
        request.setValue("keep-alive",              forHTTPHeaderField: "Connection")

        let ws = WebSocket(request: request)
        // Starscream calls delegate on its own background callbackQueue
        ws.callbackQueue = queue
        ws.delegate = self
        socket = ws
        ws.connect()

        log("Starscream connecting → \(url.absoluteString)")
    }

    private func _disconnect(intentional: Bool) {
        isIntentionalDisconnect = intentional
        isReconnectScheduled    = false

        stopHeartbeat()
        reconnectTask?.cancel()
        reconnectTask     = nil
        reconnectAttempts = 0
        pendingJoinAcks.removeAll()

        socket?.disconnect()
        socket = nil

        presenceState = presenceState.mapValues { _ in [] }
        state = .disconnected
        log("Disconnected\(intentional ? " (intentional)" : " (unexpected)")")
    }

    // MARK: - Message Handling

    private func handleText(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            log("Parse failed: \(text)")
            return
        }

        let event     = json["event"]   as? String ?? ""
        let topic     = json["topic"]   as? String ?? ""
        let payload   = json["payload"] as? [String: Any] ?? [:]
        let ref       = json["ref"]     as? String ?? ""
        let channelId = self.channelId(from: topic)

        if topic != "phoenix" {
            print(json)
        }
//        log("◀ event=\(event) channel=\(channelId) ref=\(ref)")
        
        switch event {

        case RealtimeEvent.reply.rawValue:
            guard topic != "phoenix" else {
                // Heartbeat ack — reset miss counter
                missedHeartbeats = 0
//                log("Heartbeat ack ✓")
                return
            }

            let status = payload["status"] as? String ?? ""

            // FIX: presence track fires ONLY here — after confirmed join ack.
            if let pending = pendingJoinAcks.removeValue(forKey: ref) {
                if status == "ok" {
                    log("[\(pending.channelId)] Join confirmed ✓ — tracking presence now")
                    _sendPresenceTrack(for: pending.registration)
                } else {
                    log("[\(pending.channelId)] Join failed — status: \(status)")
                }
            }

        case "presence_state":
//            print(json)
            handlePresenceState(channelId: channelId, raw: payload)

        case "presence_diff":
//            print(json)
            handlePresenceDiff(channelId: channelId, raw: payload)

        default:
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.delegate?.client(self, didReceiveMessage: json)
            }
        }
    }

    // MARK: - Presence Handlers

    private func handlePresenceState(channelId: String, raw: [String: Any]) {
        let users = parsePresenceMap(raw)
        presenceState[channelId] = users
        log("[\(channelId)] presence_state → \(users.map(\.description).joined(separator: ", "))")
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
    // FIX: Uses DispatchSourceTimer instead of Timer — no main thread dependency.
    // FIX: Tracks missed heartbeats instead of spawning new closures every interval.

    private func startHeartbeat() {
        stopHeartbeat()
        missedHeartbeats = 0
        log("Heartbeat started (every \(config.heartbeatInterval)s)")

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + config.heartbeatInterval,
                       repeating: config.heartbeatInterval)
        timer.setEventHandler { [weak self] in self?.sendHeartbeat() }
        timer.resume()
        heartbeatTimer = timer
    }

    private func stopHeartbeat() {
        heartbeatTimer?.cancel()
        heartbeatTimer = nil
    }

    private func sendHeartbeat() {
        guard state.isConnected else { return }

        // FIX: increment miss count BEFORE sending.
        // Ack handler resets it. If it reaches max, connection is dead.
        missedHeartbeats += 1
        if missedHeartbeats >= maxMissedHeartbeats {
            log("Heartbeat timeout (\(missedHeartbeats) missed) — forcing reconnect")
            _disconnect(intentional: false)
            scheduleReconnect()
            return
        }

        let ref = nextRef()
        _send([
            "topic":   "phoenix",
            "event":   RealtimeEvent.heartbeat.rawValue,
            "payload": [String: Any](),
            "ref":     ref
        ])
        log("Heartbeat sent (ref: \(ref), missed: \(missedHeartbeats))")
    }

    // MARK: - Reconnect
    // FIX: isReconnectScheduled prevents double-reconnect from Starscream
    // onDisconnect + receive failure both firing for the same drop.

    private func scheduleReconnect() {
        guard !isIntentionalDisconnect else { return }
        guard !isReconnectScheduled    else {
            log("Reconnect already scheduled — skipping duplicate")
            return
        }

        if reconnectAttempts >= config.maxReconnectAttempts {
            log("Max reconnect attempts reached — giving up")
            state = .disconnected
            return
        }

        isReconnectScheduled = true
        reconnectAttempts   += 1
        state = .reconnecting(attempt: reconnectAttempts)

        // Exponential back-off capped at 30s
        let delay = min(config.reconnectDelay * pow(2.0, Double(reconnectAttempts - 1)), 30.0)
        log("Reconnecting in \(String(format: "%.1f", delay))s (attempt \(reconnectAttempts))")

        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.queue.async { self?._connect() }
        }
    }

    // MARK: - Network Monitor
    // FIX: guard against triggering connect() when already connected/connecting.

    private func setupNetworkMonitor() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let wasAvailable = isNetworkAvailable
            let isAvailable  = path.status == .satisfied
            isNetworkAvailable = isAvailable

            if !wasAvailable && isAvailable {
                log("Network recovered")
                queue.async {
                    guard !self.state.isConnected && self.state != .connecting && !self.isIntentionalDisconnect else { return }
                    self._connect()
                }
            } else if wasAvailable && !isAvailable {
                log("Network lost")
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.supabase.realtime.network"))
        networkMonitor = monitor
    }

    // MARK: - URL Builder

    private func buildWebSocketURL() -> URL? {
        var base = config.url
            .replacingOccurrences(of: "https://", with: "wss://")
            .replacingOccurrences(of: "http://",  with: "ws://")
        if base.hasSuffix("/") { base = String(base.dropLast()) }

        var components = "\(base)/realtime/v1/websocket?apikey=\(config.apiKey)&vsn=1.0.0"

        // Append access token if present
        if let token = UserDefaults.standard.string(forKey: "access_token") {
            components += "&access_token=\(token)"
        }

        return URL(string: components)
    }

    // MARK: - Logging

    private func log(_ message: String) {
        print("[SupabaseRealtime] \(message)")
    }
}

// MARK: - Starscream WebSocketDelegate

extension SupabaseRealtimeClient: WebSocketDelegate {

    public func didReceive(event: WebSocketEvent, client: WebSocketClient) {
        // All events arrive on self.queue (set via ws.callbackQueue = queue)
        switch event {

        case .connected(let headers):
            log("Socket connected — headers: \(headers)")
            reconnectAttempts    = 0
            isReconnectScheduled = false
            state = .connected
            startHeartbeat()
            _rejoinAllChannels()

        case .disconnected(let reason, let code):
            log("Socket disconnected — code: \(code), reason: \(reason)")
            stopHeartbeat()
            if !isIntentionalDisconnect { scheduleReconnect() }
            else { state = .disconnected }

        case .text(let text):
            handleText(text)

        case .binary(let data):
            if let text = String(data: data, encoding: .utf8) { handleText(text) }

        case .error(let error):
            let msg = error?.localizedDescription ?? "unknown error"
            log("Socket error: \(msg)")
            stopHeartbeat()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if let error { self.delegate?.client(self, didFailWithError: error) }
            }
            if !isIntentionalDisconnect { scheduleReconnect() }

        case .cancelled:
            log("Socket cancelled")
            stopHeartbeat()
            state = .disconnected
            
        case .ping:
            log("Ping")
            
        case .pong:
            log("Pong")

        case .viabilityChanged(let isViable):
            log("Socket viability changed: \(isViable)")
            if !isViable && !isIntentionalDisconnect { scheduleReconnect() }

        case .reconnectSuggested(let suggested):
            log("Reconnect suggested: \(suggested)")
            if suggested && !isIntentionalDisconnect {
                _disconnect(intentional: false)
                scheduleReconnect()
            }
        case .peerClosed:
            log("Peer closed")
            stopHeartbeat()
            scheduleReconnect()
        }
    }
}

// MARK: - App Lifecycle (call from AppDelegate / SceneDelegate)

extension SupabaseRealtimeClient {

    /// Call from AppDelegate.applicationDidEnterBackground or SceneDelegate equivalent.
    public func handleAppBackground() {
        queue.async { [weak self] in
            self?.stopHeartbeat()
            self?.log("App backgrounded — heartbeat paused")
        }
    }

    /// Call from AppDelegate.applicationWillEnterForeground or SceneDelegate equivalent.
    public func handleAppForeground() {
        queue.async { [weak self] in
            guard let self else { return }
            if state.isConnected {
                startHeartbeat()
                log("App foregrounded — heartbeat resumed")
            } else if !isIntentionalDisconnect {
                log("App foregrounded — reconnecting")
                _connect()
            }
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
