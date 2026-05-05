//import Foundation
//
//// MARK: - Setup
//
//let client = SupabaseRealtimeClient(
//    config: SupabaseRealtimeConfig(
//        url: "https://YOUR_PROJECT_ID.supabase.co",
//        apiKey: "YOUR_ANON_KEY",
//        heartbeatInterval: 10.0,
//        reconnectDelay: 3.0,
//        maxReconnectAttempts: 10
//    )
//)
//
//// MARK: - Your ViewController / ViewModel
//
//class ChatRoomViewModel: SupabaseRealtimeClientDelegate {
//
//    private let client: SupabaseRealtimeClient
//    private let channelId = "room:general"
//    private let myUsername = "ali"
//
//    init(client: SupabaseRealtimeClient) {
//        self.client = client
//        self.client.delegate = self
//    }
//
//    // MARK: Lifecycle
//
//    func onAppear() {
//        client.connect()
//
//        // joinChannel can be called before connect() too —
//        // it queues automatically and joins once socket opens.
//        client.joinChannel(
//            channelId: channelId,
//            username: myUsername,
//            extraPayload: ["role": "member"]   // any extra metadata you want
//        )
//    }
//
//    func onDisappear() {
//        // Leave the channel permanently (won't rejoin on reconnect)
//        client.leaveChannel(channelId: channelId)
//
//        // Disconnect socket entirely
//        client.disconnect()
//    }
//
//    // MARK: - SupabaseRealtimeClientDelegate
//
//    func client(_ client: SupabaseRealtimeClient, didChangeState state: ConnectionState) {
//        switch state {
//        case .connected:
//            print("✅ Connected")
//
//        case .reconnecting(let attempt):
//            print("🔄 Reconnecting… attempt \(attempt)")
//            // Show reconnecting UI here
//
//        case .disconnected:
//            print("❌ Disconnected")
//
//        case .connecting:
//            print("⏳ Connecting…")
//        }
//    }
//
//    /// Full snapshot — who's already in the channel when you (re)join
//    func client(_ client: SupabaseRealtimeClient, channel: String, didReceivePresenceState users: [PresenceUser]) {
//        print("📋 [\(channel)] Current members (\(users.count)):")
//        users.forEach { print("   • \($0.username) — online since \($0.onlineAt)") }
//
//        // You can also read it anytime from:
//        // client.presenceState[channelId]
//    }
//
//    /// Incremental — someone joined or left
//    func client(_ client: SupabaseRealtimeClient, didReceivePresenceDiff diff: PresenceDiff) {
//        diff.joins.forEach { user in
//            print("➕ [\(diff.channelId)] \(user.username) joined")
//        }
//        diff.leaves.forEach { user in
//            print("➖ [\(diff.channelId)] \(user.username) left")
//        }
//
//        // After the diff, the full updated list:
//        let current = client.presenceState[diff.channelId] ?? []
//        print("👥 Online now: \(current.map(\.username).joined(separator: ", "))")
//    }
//
//    func client(_ client: SupabaseRealtimeClient, didReceiveMessage message: [String: Any]) {
//        print("📨 Message: \(message)")
//    }
//
//    func client(_ client: SupabaseRealtimeClient, didFailWithError error: Error) {
//        print("⚠️ Error: \(error.localizedDescription)")
//    }
//}
//
///*
// MARK: - What happens on disconnect + reconnect
//
// 1. Network drops / server closes connection
//       ↓
// 2. didChangeState → .reconnecting(attempt: 1)
//       ↓
// 3. Socket reconnects after delay
//       ↓
// 4. didChangeState → .connected
//       ↓
// 5. _rejoinAllChannels() fires automatically:
//       • sends phx_join  for "room:general"
//       • sends presence track for "ali"
//       ↓
// 6. Server sends back:
//       • presence_state  → didReceivePresenceState (full snapshot of who's in the room)
//       • presence_diff   → others see "ali" rejoin
//       ↓
// 7. Your UI is fully restored — zero manual work needed
//
// MARK: - Multiple channels
//
// client.joinChannel(channelId: "room:general",  username: "ali")
// client.joinChannel(channelId: "room:vip",      username: "ali")
// client.joinChannel(channelId: "notifications", username: "ali")
//
// // All three auto-rejoin after any reconnect.
// // Leave one without affecting the others:
// client.leaveChannel(channelId: "room:vip")
//*/
