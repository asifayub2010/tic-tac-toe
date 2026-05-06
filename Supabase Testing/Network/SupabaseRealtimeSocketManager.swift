//
//  SupabaseRealtimeSocketManager.swift
//  Supabase Testing
//
//  Created by mac on 07/05/2026.
//


import Foundation
import Starscream

final class SupabaseRealtimeSocketManager: NSObject {

    // MARK: - Properties

    private var socket: WebSocket?
    private var reconnectWorkItem: DispatchWorkItem?

    private let queue = DispatchQueue(label: "socket.queue")

    private var isManuallyDisconnected = false
    private var pingTimer: Timer?

    // Replace with your values
    private let apiKey = "sb_publishable_PhNhE083zZ3FMjOBbsxeXw_wMT6k8-o"

    private lazy var socketURL: URL = {
        var components = URLComponents()
        components.scheme = "wss"
        components.host = "eilxfocmlnzsjkrgbvvv.supabase.co"
        components.path = "/realtime/v1/websocket"

        components.queryItems = [
            URLQueryItem(name: "apikey", value: apiKey),
            URLQueryItem(name: "vsn", value: "1.0.0")
        ]

        return components.url!
    }()

    // MARK: - Connect

    func connect() {
        isManuallyDisconnected = false

        var request = URLRequest(url: socketURL)
        request.timeoutInterval = 10

        socket = WebSocket(request: request)
        socket?.delegate = self
        socket?.connect()
    }

    // MARK: - Disconnect

    func disconnect() {
        isManuallyDisconnected = true

        stopPing()

        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil

        socket?.disconnect()
        socket = nil
    }

    // MARK: - Ping

    private func startPing() {
        stopPing()

        DispatchQueue.main.async {
            self.pingTimer = Timer.scheduledTimer(withTimeInterval: 15,
                                                  repeats: true) { [weak self] _ in
                guard let self = self else { return }

                self.socket?.write(ping: Data())
                print("➡️ Ping")
            }
        }
    }

    private func stopPing() {
        pingTimer?.invalidate()
        pingTimer = nil
    }

    // MARK: - Reconnect

    private func reconnect() {
        guard !isManuallyDisconnected else { return }

        reconnectWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }

            print("🔄 Reconnecting...")
            self.connect()
        }

        reconnectWorkItem = workItem

        queue.asyncAfter(deadline: .now() + 3,
                         execute: workItem)
    }

    // MARK: - Join Realtime Topic

    func joinRoom(topic: String) {
        let payload: [String: Any] = [
            "topic": topic,
            "event": "phx_join",
            "payload": [:],
            "ref": "1"
        ]

        send(payload)
    }

    // MARK: - Send

    func send(_ dictionary: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dictionary),
              let json = String(data: data, encoding: .utf8) else {
            return
        }

        socket?.write(string: json)
        print("⬆️ Sent:", json)
    }
}

// MARK: - WebSocketDelegate

extension SupabaseRealtimeSocketManager: WebSocketDelegate {

    func didReceive(event: WebSocketEvent, client: WebSocketClient) {

        switch event {

        case .connected(let headers):
            print("✅ Connected")
            print(headers)

            startPing()

        case .disconnected(let reason, let code):
            print("❌ Disconnected")
            print(reason, code)

            stopPing()
            reconnect()

        case .text(let text):
            print("📩 Text:", text)

        case .binary(let data):
            print("📦 Binary:", data)

        case .pong(_):
            print("⬅️ Pong")

        case .ping(_):
            print("⬅️ Ping")

        case .error(let error):
            print("🚨 Error:", error?.localizedDescription ?? "")

            stopPing()
            reconnect()

        case .cancelled:
            print("⛔️ Cancelled")

            stopPing()
            reconnect()

        case .peerClosed:
            print("👋 Peer Closed")

            stopPing()
            reconnect()

        case .viabilityChanged(let isViable):
            print("📶 Viable:", isViable)

        case .reconnectSuggested(let suggested):
            print("♻️ Reconnect Suggested:", suggested)
        }
    }
}
