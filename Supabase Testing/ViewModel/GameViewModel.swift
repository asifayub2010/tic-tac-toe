////
////  GameViewModel.swift
////  Supabase Testing
////
////  Created by mac on 02/05/2026.
////
//
//
//// ViewModels/GameViewModel.swift
//
//import Foundation
//import SwiftUI
//import Combine
//
//class GameViewModel: ObservableObject {
//    // MARK: - Published Properties
//    @Published var playerName: String
//    @Published var roomId: String = ""
//    @Published var isInRoom: Bool = false
//    @Published var messageText: String = ""
//    @Published var messages: [String] = []
//    @Published var connectionStatus: String = "Disconnected"
//    @Published var isConnected = false
//    
//    // MARK: - Private Properties
//    private let realtimeClient: RealtimeClient
//    private var cancellables = Set<AnyCancellable>()
//    
//    // MARK: - Initialization
//    init(playerName: String, realtimeClient: RealtimeClient) {
//        self.playerName = playerName
//        self.realtimeClient = realtimeClient
//        
//        // Bind to realtime client
//        realtimeClient.$isConnected
//            .receive(on: DispatchQueue.main)
//            .assign(to: &$isConnected)
//        
//        realtimeClient.$lastMessage
//            .receive(on: DispatchQueue.main)
//            .sink { [weak self] message in
//                if !message.isEmpty {
//                    self?.messages.append(message)
//                }
//            }
//            .store(in: &cancellables)
//        
//        realtimeClient.$errorMessage
//            .receive(on: DispatchQueue.main)
//            .sink { error in
//                if let error = error {
//                    print("Error: \(error)")
//                }
//            }
//            .store(in: &cancellables)
//        
//        updateConnectionStatus()
//    }
//    
//    // MARK: - Public Methods
//    func connect() async {
//        await realtimeClient.connect()
//        updateConnectionStatus()
//    }
//    
//    func disconnect() async {
//        await realtimeClient.disconnect()
//        isInRoom = false
//        roomId = ""
//        updateConnectionStatus()
//    }
//    
//    func joinRoom() async {
//        guard !roomId.isEmpty else { return }
//        await realtimeClient.joinRoom(roomId: roomId, playerName: playerName)
//        isInRoom = true
//    }
//    
//    func leaveRoom() async {
//        await realtimeClient.leaveRoom()
//        isInRoom = false
//    }
//    
//    func sendMessage() {
//        guard !messageText.isEmpty else { return }
//        realtimeClient.sendMessage(messageText)
//        messageText = ""
//    }
//    
//    private func updateConnectionStatus() {
//        connectionStatus = isConnected ? "Connected" : "Disconnected"
//    }
//}
