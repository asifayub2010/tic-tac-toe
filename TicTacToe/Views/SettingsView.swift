//
//  SettingsView.swift
//  TicTacToe
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: GameViewModel
    @Binding var isGameStarted: Bool
    
    @State private var selectedMode: PlayerCount = .two
    @State private var isOnline: Bool = false
    @State private var roomId: String = ""
    @State private var p1Name: String = "Player 1"
    @State private var p2Name: String = "Player 2"
    @State private var p3Name: String = "Player 3"
    
    @State private var isJoining = false
    @State private var isLoading = false
    
    enum PlayerCount: Int {
        case one = 1
        case two = 2
        case three = 3
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Play Mode")) {
                    Picker("Players", selection: $selectedMode) {
                        Text("1 Player").tag(PlayerCount.one)
                        Text("2 Players").tag(PlayerCount.two)
                        Text("3 Players").tag(PlayerCount.three)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .onChange(of: selectedMode) { _ in updateNames() }
                    
                    if selectedMode != .one {
                        Toggle("Online Multiplayer", isOn: $isOnline)
                    }
                }
                
                if isOnline {
                    Section(header: Text("Online Game")) {
                        if !isJoining {
                            Button(action: createOnlineGame) {
                                if isLoading {
                                    ProgressView().tint(.blue)
                                } else {
                                    Text("Create Room")
                                }
                            }
                            .disabled(isLoading)
                            
                            Divider()
                            
                            Button("Join Existing Room") {
                                withAnimation { isJoining = true }
                            }
                        } else {
                            TextField("Enter Room ID", text: $roomId)
                                .textInputAutocapitalization(.characters)
                            
                            Button(action: joinOnlineGame) {
                                if isLoading {
                                    ProgressView().tint(.blue)
                                } else {
                                    Text("Join Game")
                                }
                            }
                            .disabled(roomId.isEmpty || isLoading)
                            
                            Button("Cancel") {
                                withAnimation { isJoining = false }
                            }
                            .foregroundColor(.red)
                        }
                    }
                }
                
                Section(header: Text("Player Names")) {
                    TextField(isOnline ? "Your Name (X)" : "Player 1 (X)", text: $p1Name)
                    
                    if selectedMode != .one && !isOnline {
                        TextField("Player 2 (O)", text: $p2Name)
                        if selectedMode == .three {
                            TextField("Player 3 (Y)", text: $p3Name)
                        }
                    } else if selectedMode == .one {
                        Text("Player 2: AI (O)").foregroundColor(.secondary)
                    } else if isOnline {
                        Text("Opponents will join via Room ID").foregroundColor(.secondary).font(.caption)
                    }
                }
                
                if !isOnline {
                    Section {
                        Button(action: startOfflineGame) {
                            Text("Start Offline Game")
                                .frame(maxWidth: .infinity)
                                .bold()
                        }
                        .listRowBackground(Color.blue)
                        .foregroundColor(.white)
                    }
                }
            }
            .navigationTitle("TicTacToe")
            .onAppear {
                if isOnline {
                    Task { try? await viewModel.connect()}
                }
            }
            .onChange(of: isOnline) { newValue in
                if newValue {
                    Task { try? await viewModel.connect()}
                } else {
                    viewModel.disconnect()
                }
            }
        }
    }
    
    private func updateNames() {
        if selectedMode == .one {
            isOnline = false
            p1Name = "Player"
            p2Name = "AI"
        }
    }
    
    private func startOfflineGame() {
        let mode: GameMode
        var names: [Player: String] = [.x: p1Name, .o: p2Name]
        
        switch selectedMode {
        case .one:
            mode = .singlePlayer
        case .two:
            mode = .twoPlayerOffline
        case .three:
            mode = .threePlayerOffline
            names[.y] = p3Name
        }
        
        viewModel.configureGame(mode: mode, names: names)
        isGameStarted = true
    }
    
    private func createOnlineGame() {
        isLoading = true
        let mode: GameMode = selectedMode == .two ? .twoPlayerOnline(roomId: "", isHost: true) : .threePlayerOnline(roomId: "", isHost: true)
        
        Task {
            if let id = await viewModel.createRoom(mode: mode) {
                await MainActor.run {
                    isLoading = false
                    let finalMode: GameMode = selectedMode == .two ? 
                        .twoPlayerOnline(roomId: id, isHost: true) : 
                        .threePlayerOnline(roomId: id, isHost: true)
                    
                    var names: [Player: String] = [.x: p1Name, .o: "Waiting...", .y: "Waiting..."]
                    viewModel.configureGame(mode: finalMode, names: names, myPlayer: .x)
                    isGameStarted = true
                    
                    // Copy ID to clipboard
                    UIPasteboard.general.string = id
                }
            } else {
                await MainActor.run { isLoading = false }
            }
        }
    }
    
    private func joinOnlineGame() {
        isLoading = true
        let mode: GameMode = selectedMode == .two ? 
            .twoPlayerOnline(roomId: roomId, isHost: false) : 
            .threePlayerOnline(roomId: roomId, isHost: false)
            
        Task {
            await viewModel.joinRoom(roomId: roomId, mode: mode)
            await MainActor.run {
                isLoading = false
                // For simplicity, we assume joiner is Player O (for 2p) or O/Y (for 3p)
                // In a real app, the service would assign this
                
                // We'll set a default for now, the 'join' event would sync names
                viewModel.configureGame(mode: mode, names: [.x: "Host", .o: p1Name, .y: "Player 3"], myPlayer: .o)
                isGameStarted = true
            }
        }
    }
}
