//import Foundation
//import Network
////import UIKit
//
//// MARK: - Configuration
//
//public struct SupabaseRealtimeConfig {
//    public let url: String
//    public let apiKey: String
//    public var heartbeatInterval: TimeInterval
//    public var reconnectDelay: TimeInterval
//    public var maxReconnectAttempts: Int
//    public var connectionTimeout: TimeInterval
//    
//    public init(
//        url: String,
//        apiKey: String,
//        heartbeatInterval: TimeInterval = 15.0,
//        reconnectDelay: TimeInterval = 1.0,
//        maxReconnectAttempts: Int = Int.max,
//        connectionTimeout: TimeInterval = 60.0
//    ) {
//        self.url = url
//        self.apiKey = apiKey
//        self.heartbeatInterval = heartbeatInterval
//        self.reconnectDelay = reconnectDelay
//        self.maxReconnectAttempts = maxReconnectAttempts
//        self.connectionTimeout = connectionTimeout
//    }
//}
//
//public enum Event: String {
//    case join = "phx_join"
//    case presence = "presence"
//    case broadcast = "broadcast"
//    case move = "move"
//}
//
//// MARK: - Connection State
//
//public enum ConnectionState: Equatable {
//    case disconnected
//    case connecting
//    case connected
//    case reconnecting(attempt: Int)
//    
//    public var isConnected: Bool { self == .connected }
//    
//    public var description: String {
//        switch self {
//        case .disconnected: return "Disconnected"
//        case .connecting: return "Connecting"
//        case .connected: return "Connected"
//        case .reconnecting(let n): return "Reconnecting (attempt \(n))"
//        }
//    }
//}
//
//// MARK: - Presence Models
//
//public struct PresenceUser: Equatable {
//    public let key: String
//    public let username: String
//    public let onlineAt: String
//    public let phxRef: String
//    
//    public var description: String { "\(username) [\(key)]" }
//}
//
//public struct PresenceDiff {
//    public let channelId: String
//    public let joins: [PresenceUser]
//    public let leaves: [PresenceUser]
//}
//
//// MARK: - Internal Models
//
//private struct ChannelRegistration {
//    let channelId: String
//    let presenceKey: String
//    let presencePayload: [String: Any]
//}
//
//private struct PendingJoinAck {
//    let channelId: String
//    let registration: ChannelRegistration
//}
//
//// MARK: - Delegate
//
//public protocol SupabaseRealtimeClientDelegate: AnyObject {
//    func client(_ client: SupabaseRealtimeClient, didChangeState state: ConnectionState)
//    func client(_ client: SupabaseRealtimeClient, channel: String, didReceivePresenceState users: [PresenceUser])
//    func client(_ client: SupabaseRealtimeClient, didReceivePresenceDiff diff: PresenceDiff)
//    func client(_ client: SupabaseRealtimeClient, didReceiveMessage message: [String: Any])
//    func client(_ client: SupabaseRealtimeClient, didFailWithError error: Error)
//}
//
//// MARK: - Client
//
//public final class SupabaseRealtimeClient: NSObject {
//    
//    // MARK: Public Properties
//    public private(set) var state: ConnectionState = .disconnected {
//        didSet {
//            guard state != oldValue else { return }
//            log("State → \(state.description)")
//            DispatchQueue.main.async { [weak self] in
//                guard let self = self else { return }
//                self.delegate?.client(self, didChangeState: state)
//            }
//        }
//    }
//    
//    public weak var delegate: SupabaseRealtimeClientDelegate?
//    public private(set) var presenceState: [String: [PresenceUser]] = [:]
//    
//    // MARK: Private Properties
//    private let config: SupabaseRealtimeConfig
//    private var webSocketTask: URLSessionWebSocketTask?
//    private var urlSession: URLSession?
//    private var heartbeatTimer: Timer?
//    private var globalRef: Int = 0
//    private var reconnectTask: Task<Void, Never>?
//    private var reconnectAttempts: Int = 0
//    private var isIntentionalDisconnect: Bool = false
//    private var channelRegistry: [String: ChannelRegistration] = [:]
//    private var pendingJoinAcks: [String: PendingJoinAck] = [:]
//    private var networkMonitor: NWPathMonitor?
//    private var isNetworkAvailable: Bool = true
//    private var lastHeartbeatTime: Date?
//    private var heartbeatFailureCount: Int = 0
//    private let queue = DispatchQueue(label: "com.supabase.realtime.client", qos: .utility)
//    
//    // MARK: Init
//    public init(config: SupabaseRealtimeConfig) {
//        self.config = config
//        super.init()
//        setupNetworkMonitoring()
//        setupAppLifecycleObservers()
//    }
//    
//    deinit {
//        networkMonitor?.cancel()
//        NotificationCenter.default.removeObserver(self)
//    }
//    
//    // MARK: - Public Methods
//    
//    public func connect() {
//        queue.async { [weak self] in
//            self?._connect()
//        }
//    }
//    
//    public func disconnect() {
//        queue.async { [weak self] in
//            self?._disconnect(intentional: true)
//        }
//    }
//    
//    public func joinChannel(
//        channelId: String,
//        username: String,
//        extraPayload: [String: Any] = [:]
//    ) {
//        queue.async { [weak self] in
//            guard let self else { return }
//            
//            guard self.channelRegistry[channelId] == nil else {
//                self.log("[\(channelId)] Already registered — skipping duplicate join")
//                return
//            }
//            
//            var payload: [String: Any] = [
//                "type": "presence",
//                "event": "track",  // Add this explicitly
////                "payload": reg.presencePayload,
//                "key": username,
//                "username": username,
//                "online_at": ISO8601DateFormatter().string(from: Date())
//            ]
//            extraPayload.forEach { payload[$0.key] = $0.value }
//            
//            let reg = ChannelRegistration(
//                channelId: channelId,
//                presenceKey: username,
//                presencePayload: payload
//            )
//            
//            self.channelRegistry[channelId] = reg
//            self.presenceState[channelId] = []
//            
//            if self.state.isConnected {
//                self._sendJoin(reg)
//            } else {
//                self.log("[\(channelId)] Queued — will join once socket connects")
//            }
//        }
//    }
//    
//    public func leaveChannel(channelId: String) {
//        queue.async { [weak self] in
//            guard let self else { return }
//            
//            self.channelRegistry.removeValue(forKey: channelId)
//            self.presenceState.removeValue(forKey: channelId)
//            self.pendingJoinAcks = self.pendingJoinAcks.filter { $0.value.channelId != channelId }
//            
//            guard self.state.isConnected else { return }
//            
//            self._send([
//                "topic": self.topic(for: channelId),
//                "event": "phx_leave",
//                "payload": [:],
//                "ref": self.nextRef()
//            ])
//            self.log("[\(channelId)] Left and removed from registry")
//        }
//    }
//    
//    public func send(_ payload: [String: Any], completion: ((Error?) -> Void)? = nil) {
//        guard state.isConnected else {
//            completion?(RealtimeError.notConnected)
//            return
//        }
//        
//        queue.async { [weak self] in
//            guard let self = self else { return }
//            guard let data = try? JSONSerialization.data(withJSONObject: payload),
//                  let text = String(data: data, encoding: .utf8) else {
//                completion?(RealtimeError.serializationFailed)
//                return
//            }
//            self.webSocketTask?.send(.string(text)) { error in
//                if let error = error {
//                    self.log("Send error: \(error.localizedDescription)")
//                }
//                completion?(error)
//            }
//        }
//    }
//    
//    public func broadcastMove(x: String, y: String, player: String, channelId: String) {
//        queue.async { [weak self] in
//            guard let self else { return }
//            
//            let broadcastPayload: [String: Any] = [
//                "topic": self.topic(for: channelId),
//                "event": Event.broadcast.rawValue,
//                "payload": [
//                    "event": Event.move.rawValue,
//                    "payload": [
//                        "player": player,
//                        "x": x,
//                        "y": y
//                    ]
//                ],
//                "ref": self.nextRef()
//            ]
//            
//            if self.state.isConnected {
//                self._send(broadcastPayload)
//            } else {
//                self.log("[\(channelId)] Cannot broadcast - not connected")
//            }
//        }
//    }
//    
//    // MARK: - Private Methods
//    
//    private func _sendJoin(_ reg: ChannelRegistration) {
//        let joinRef = nextRef()
//        pendingJoinAcks[joinRef] = PendingJoinAck(channelId: reg.channelId, registration: reg)
//        
//        _send([
//            "topic": topic(for: reg.channelId),
//            "event": Event.join.rawValue,
//            "payload": [
//                "config": [
//                    "presence": ["enabled": true, "key": reg.presenceKey],
//                    "broadcast": ["self": true, "ack": true]
//                ]
//            ],
//            "ref": joinRef,
//            "join_ref": joinRef
//        ])
//        log("[\(reg.channelId)] phx_join sent (ref: \(joinRef))")
//    }
//    
//    private func _sendPresenceTrack(for reg: ChannelRegistration) {
//        let trackRef = nextRef()
//        /*
//         // CRITICAL FIX: Supabase expects the presence payload in this exact format
//             let presencePayload: [String: Any] = [
//                 "type": "presence",
//                 "event": "track",  // Add this explicitly
//                 "payload": reg.presencePayload,
//                 "key": reg.presenceKey
//             ]
//             
//             _send([
//                 "topic": topic(for: reg.channelId),
//                 "event": "presence",  // Use string literal, not enum
//                 "payload": presencePayload,
//                 "ref": trackRef
//             ])
//         */
//        _send([
//            "topic": topic(for: reg.channelId),
//            "event": Event.presence.rawValue,
//            "payload": reg.presencePayload,
////                [
////                "type": "track",
////                "key": reg.presenceKey,
////                "payload": reg.presencePayload
////            ],
//            "ref": trackRef
//        ])
//        log("[\(reg.channelId)] presence track sent (ref: \(trackRef))")
//        
//    }
//    
//    private func _rejoinAllChannels() {
//        guard !channelRegistry.isEmpty else { return }
//        pendingJoinAcks.removeAll()
//        log("Auto-rejoining \(channelRegistry.count) channel(s)...")
//        for reg in channelRegistry.values {
//            _sendJoin(reg)
//        }
//    }
//    
//    private func _send(_ payload: [String: Any]) {
//        guard let data = try? JSONSerialization.data(withJSONObject: payload),
//              let text = String(data: data, encoding: .utf8) else { return }
//        webSocketTask?.send(.string(text)) { [weak self] error in
//            if let error = error {
//                self?.log("Send error: \(error.localizedDescription)")
//            }
//        }
//    }
//    
//    private func nextRef() -> String {
//        globalRef += 1
//        return "\(globalRef)"
//    }
//    
//    private func topic(for channelId: String) -> String {
//        return "realtime:\(channelId)"
//    }
//    
//    private func channelId(from topic: String) -> String {
//        guard topic.hasPrefix("realtime:") else { return topic }
//        return String(topic.dropFirst("realtime:".count))
//    }
//    
//    // MARK: - Connection Management
//    
//    private func _connect() {
//        guard !state.isConnected && state != .connecting else {
//            log("Already \(state.description) — ignoring connect()")
//            return
//        }
//        
//        isIntentionalDisconnect = false
//        reconnectAttempts = 0
//        state = .connecting
//        
//        guard let url = buildWebSocketURL() else {
//            log("Invalid WebSocket URL")
//            state = .disconnected
//            return
//        }
//        
//        let configuration = URLSessionConfiguration.default
//        configuration.waitsForConnectivity = true
//        configuration.timeoutIntervalForRequest = config.connectionTimeout
//        configuration.timeoutIntervalForResource = config.connectionTimeout * 2
//        
//        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: .main)
//        urlSession = session
//        
//        var request = URLRequest(url: url, timeoutInterval: config.connectionTimeout)
//        request.setValue(config.apiKey, forHTTPHeaderField: "apikey")
//        request.setValue("keep-alive", forHTTPHeaderField: "Connection")
//        
//        let task = session.webSocketTask(with: request)
//        webSocketTask = task
//        task.resume()
//        
//        listenForMessages()
//        log("WebSocket connecting → \(url.absoluteString)")
//    }
//    
//    private func _disconnect(intentional: Bool) {
//        isIntentionalDisconnect = intentional
//        stopHeartbeat()
//        reconnectTask?.cancel()
//        reconnectTask = nil
//        reconnectAttempts = 0
//        pendingJoinAcks.removeAll()
//        
//        webSocketTask?.cancel(with: .goingAway, reason: nil)
//        webSocketTask = nil
//        urlSession?.invalidateAndCancel()
//        urlSession = nil
//        
//        presenceState = presenceState.mapValues { _ in [] }
//        state = .disconnected
//        log("Disconnected\(intentional ? " (intentional)" : "")")
//    }
//    
//    // MARK: - Message Handling
//    
//    private func listenForMessages() {
//        webSocketTask?.receive { [weak self] result in
//            guard let self = self else { return }
//            
//            switch result {
//            case .success(let message):
//                self.handleIncoming(message)
//                if !self.isIntentionalDisconnect {
//                    self.listenForMessages()
//                }
//            case .failure(let error):
//                self.log("Receive error: \(error.localizedDescription)")
//                if !self.isIntentionalDisconnect {
//                    self.scheduleReconnect()
//                }
//            }
//        }
//    }
//    
//    private func handleIncoming(_ message: URLSessionWebSocketTask.Message) {
//        var text: String?
//        switch message {
//        case .string(let s):
//            text = s
//        case .data(let d):
//            text = String(data: d, encoding: .utf8)
//        @unknown default:
//            break
//        }
//        
//        guard let raw = text,
//              let data = raw.data(using: .utf8),
//              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
//            log("Could not parse incoming message")
//            return
//        }
//        
//        let event = json["event"] as? String ?? ""
//        let topic = json["topic"] as? String ?? ""
//        let payload = json["payload"] as? [String: Any] ?? [:]
//        let ref = json["ref"] as? String ?? ""
//        let channelId = self.channelId(from: topic)
//        
//        switch event {
//        case "phx_reply":
//            if topic == "phoenix" {
//                lastHeartbeatTime = Date()
//                heartbeatFailureCount = 0
//                log("Heartbeat ack ✓")
//                return
//            }
//            
//            let status = payload["status"] as? String ?? ""
//            if let pending = pendingJoinAcks.removeValue(forKey: ref), status == "ok" {
//                log("[\(pending.channelId)] Join confirmed ✓")
//                _sendPresenceTrack(for: pending.registration)
//            }
//            
//            /*
//             let presencePayload: [String: Any] = [
//                 "type": "presence",
//                 "event": "track",  // Add this explicitly
//                 "payload": reg.presencePayload,
//                 "key": reg.presenceKey
//             ]
//             */
//            
//        case "presence_state":
//            handlePresenceState(channelId: channelId, raw: payload)
//            
//        case "presence_diff":
//            handlePresenceDiff(channelId: channelId, raw: payload)
//            
//        default:
//            DispatchQueue.main.async { [weak self] in
//                guard let self = self else { return }
//                self.delegate?.client(self, didReceiveMessage: json)
//            }
//        }
//    }
//    
//    // MARK: - Presence Handlers
//    
//    private func handlePresenceState(channelId: String, raw: [String: Any]) {
//        let users = parsePresenceMap(raw)
//        presenceState[channelId] = users
//        
//        DispatchQueue.main.async { [weak self] in
//            guard let self = self else { return }
//            self.delegate?.client(self, channel: channelId, didReceivePresenceState: users)
//        }
//    }
//    
//    private func handlePresenceDiff(channelId: String, raw: [String: Any]) {
//        let joins = parsePresenceMap(raw["joins"] as? [String: Any] ?? [:])
//        let leaves = parsePresenceMap(raw["leaves"] as? [String: Any] ?? [:])
//        
//        var current = presenceState[channelId] ?? []
//        let leaveRefs = Set(leaves.map { $0.phxRef })
//        current.removeAll { leaveRefs.contains($0.phxRef) }
//        
//        let existingRefs = Set(current.map { $0.phxRef })
//        current.append(contentsOf: joins.filter { !existingRefs.contains($0.phxRef) })
//        presenceState[channelId] = current
//        
//        let diff = PresenceDiff(channelId: channelId, joins: joins, leaves: leaves)
//        DispatchQueue.main.async { [weak self] in
//            guard let self = self else { return }
//            self.delegate?.client(self, didReceivePresenceDiff: diff)
//        }
//    }
//    
//    private func parsePresenceMap(_ map: [String: Any]) -> [PresenceUser] {
//        return map.compactMap { key, value -> PresenceUser? in
//            guard let entry = value as? [String: Any],
//                  let metas = entry["metas"] as? [[String: Any]],
//                  let meta = metas.first else { return nil }
//            return PresenceUser(
//                key: key,
//                username: meta["username"] as? String ?? key,
//                onlineAt: meta["online_at"] as? String ?? "",
//                phxRef: meta["phx_ref"] as? String ?? ""
//            )
//        }
//    }
//    
//    // MARK: - Heartbeat
//    
//    private func startHeartbeat() {
//        stopHeartbeat()
//        log("Heartbeat started (every \(config.heartbeatInterval)s)")
//        
//        DispatchQueue.main.async { [weak self] in
//            guard let self = self else { return }
//            self.heartbeatTimer = Timer.scheduledTimer(
//                withTimeInterval: self.config.heartbeatInterval,
//                repeats: true
//            ) { [weak self] _ in
//                self?.sendHeartbeat()
//            }
//        }
//    }
//    
//    private func stopHeartbeat() {
//        DispatchQueue.main.async { [weak self] in
//            self?.heartbeatTimer?.invalidate()
//            self?.heartbeatTimer = nil
//        }
//    }
//    
//    private func sendHeartbeat() {
//        guard state.isConnected else { return }
//        
//        let ref = nextRef()
//        queue.async { [weak self] in
//            guard let self = self else { return }
//            self._send([
//                "topic": "phoenix",
//                "event": "heartbeat",
//                "payload": [:],
//                "ref": ref
//            ])
//            self.log("Heartbeat sent (ref: \(ref))")
//        }
//        
//        // Check for heartbeat timeout
//        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
//            if let lastTime = self?.lastHeartbeatTime,
//               Date().timeIntervalSince(lastTime) > self?.config.heartbeatInterval ?? 15 {
//                self?.heartbeatFailureCount += 1
//                if self?.heartbeatFailureCount ?? 0 >= 3 {
//                    self?.log("Heartbeat timeout, forcing reconnect")
//                    self?.forceReconnect()
//                }
//            }
//        }
//    }
//    
//    private func forceReconnect() {
//        queue.async { [weak self] in
//            self?._disconnect(intentional: false)
//            self?.scheduleReconnect()
//        }
//    }
//    
//    // MARK: - Reconnect Logic
//    
//    private func scheduleReconnect() {
//        guard !isIntentionalDisconnect else { return }
//        
//        if reconnectAttempts >= config.maxReconnectAttempts {
//            log("Max reconnect attempts reached")
//            state = .disconnected
//            return
//        }
//        
//        reconnectAttempts += 1
//        state = .reconnecting(attempt: reconnectAttempts)
//        
//        let delay = min(config.reconnectDelay * Double(reconnectAttempts), 30)
//        log("Will reconnect in \(delay)s (attempt \(reconnectAttempts))")
//        
//        reconnectTask = Task { [weak self] in
//            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
//            guard !Task.isCancelled else { return }
//            await MainActor.run {
//                self?._connect()
//            }
//        }
//    }
//    
//    // MARK: - Network Monitoring
//    
//    private func setupNetworkMonitoring() {
//        networkMonitor = NWPathMonitor()
//        networkMonitor?.pathUpdateHandler = { [weak self] path in
//            let wasAvailable = self?.isNetworkAvailable ?? false
//            let isAvailable = path.status == .satisfied
//            self?.isNetworkAvailable = isAvailable
//            
//            if !wasAvailable && isAvailable {
//                self?.log("Network recovered, reconnecting...")
//                self?.connect()
//            } else if wasAvailable && !isAvailable {
//                self?.log("Network lost")
//            }
//        }
//        networkMonitor?.start(queue: .main)
//    }
//    
//    // MARK: - App Lifecycle
//    
//    private func setupAppLifecycleObservers() {
////        NotificationCenter.default.addObserver(
////            self,
////            selector: #selector(appDidEnterBackground),
////            name: UIApplication.didEnterBackgroundNotification,
////            object: nil
////        )
////        
////        NotificationCenter.default.addObserver(
////            self,
////            selector: #selector(appWillEnterForeground),
////            name: UIApplication.willEnterForegroundNotification,
////            object: nil
////        )
//    }
//    
//    @objc private func appDidEnterBackground() {
//        stopHeartbeat()
//    }
//    
//    @objc private func appWillEnterForeground() {
//        if !state.isConnected && !isIntentionalDisconnect {
//            connect()
//        } else {
//            startHeartbeat()
//        }
//    }
//    
//    // MARK: - URL Building
//    
//    private func buildWebSocketURL() -> URL? {
//        var base = config.url
//            .replacingOccurrences(of: "https://", with: "wss://")
//            .replacingOccurrences(of: "http://", with: "ws://")
//        if base.hasSuffix("/") {
//            base = String(base.dropLast())
//        }
//        
//        var urlString = "\(base)/realtime/v1/websocket?apikey=\(config.apiKey)&vsn=1.0.0"
//        
//        if let jwtToken = UserDefaults.standard.string(forKey: "access_token") {
//            urlString += "&access_token=\(jwtToken)"
//        }
//        
//        return URL(string: urlString)
//    }
//    
//    // MARK: - Logging
//    
//    private func log(_ message: String) {
//        print("[SupabaseRealtime] \(message)")
//    }
//}
//
//// MARK: - URLSessionWebSocketDelegate
//
//extension SupabaseRealtimeClient: URLSessionWebSocketDelegate {
//    
//    public func urlSession(
//        _ session: URLSession,
//        webSocketTask: URLSessionWebSocketTask,
//        didOpenWithProtocol protocol: String?
//    ) {
//        queue.async { [weak self] in
//            guard let self = self else { return }
//            self.reconnectAttempts = 0
//            self.state = .connected
//            self.lastHeartbeatTime = Date()
//            self.heartbeatFailureCount = 0
//            self.startHeartbeat()
//            self._rejoinAllChannels()
//        }
//    }
//    
//    public func urlSession(
//        _ session: URLSession,
//        webSocketTask: URLSessionWebSocketTask,
//        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
//        reason: Data?
//    ) {
//        let reasonString = reason.flatMap { String(data: $0, encoding: .utf8) } ?? "none"
//        log("Socket closed — code: \(closeCode.rawValue), reason: \(reasonString)")
//        
//        queue.async { [weak self] in
//            guard let self = self else { return }
//            self.stopHeartbeat()
//            
//            if !self.isIntentionalDisconnect {
//                self.scheduleReconnect()
//            } else {
//                self.state = .disconnected
//            }
//        }
//    }
//    
//    public func urlSession(
//        _ session: URLSession,
//        task: URLSessionTask,
//        didCompleteWithError error: Error?
//    ) {
//        if let error = error {
//            log("Task error: \(error.localizedDescription)")
//            
//            queue.async { [weak self] in
//                guard let self = self else { return }
//                self.stopHeartbeat()
//                DispatchQueue.main.async {
//                    self.delegate?.client(self, didFailWithError: error)
//                }
//                
//                if !self.isIntentionalDisconnect {
//                    self.scheduleReconnect()
//                }
//            }
//        }
//    }
//}
//
//// MARK: - Errors
//
//public enum RealtimeError: LocalizedError {
//    case notConnected
//    case serializationFailed
//    
//    public var errorDescription: String? {
//        switch self {
//        case .notConnected:
//            return "WebSocket is not connected"
//        case .serializationFailed:
//            return "Failed to serialize message"
//        }
//    }
//}
