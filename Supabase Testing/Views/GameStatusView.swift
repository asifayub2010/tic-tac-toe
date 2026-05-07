//
//  ContentView 2.swift
//  Supabase Testing
//
//  Created by mac on 05/05/2026.
//


import SwiftUI

struct GameStatusView: View {
    @StateObject private var viewModel: GameViewModel
    
    init(currentPlayerName: String) {
        _viewModel = StateObject(
            wrappedValue: GameViewModel(playerName: currentPlayerName)
        )
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Lobby")
                .font(.largeTitle.bold())
            
            Text("Player: \(viewModel.playerName)")
                .font(.headline)
            
            HStack {
                Text(viewModel.connectionStatus)
                    .foregroundStyle(viewModel.isConnected ? .green : .red)
                
                Spacer()
                
                Button(viewModel.isConnected ? "Disconnect" : "Connect") {
                    if viewModel.isConnected {
                        viewModel.disconnect()
                    } else {
                        viewModel.connect()
                    }
                }
            }
            
            HStack {
                Button("Join Lobby") {
                    viewModel.joinLobby()
                }
                .disabled(!viewModel.isConnected || viewModel.activeGameRoomId != nil)
                
                Spacer()
                
                if viewModel.activeGameRoomId != nil {
                    Button("Leave Game Room") {
                        viewModel.leaveGameRoom()
                    }
                }
            }
            
            Divider()
            
            Text("Online Players \(viewModel.onlinePlayers.joined(separator: ", "))")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            List(viewModel.onlinePlayers, id: \.self) { player in
                HStack {
                    Text(player)
                        .onAppear {
                            print("player joined: ", player)
                        }
                    Spacer()
                    if viewModel.selectedPlayer == player {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.blue)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    viewModel.selectedPlayer = player
                }
            }
            .frame(maxHeight: 260)

            Button("Invite Selected Player") {
                viewModel.sendInvite()
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.selectedPlayer == nil || viewModel.activeGameRoomId != nil)
            
            if let pendingInviteTo = viewModel.pendingInviteTo {
                Text("Waiting for \(pendingInviteTo) to respond...")
                    .font(.subheadline)
            }
            
            if let incomingInviteFrom = viewModel.incomingInviteFrom {
                VStack(spacing: 8) {
                    Text("\(incomingInviteFrom) invited you to play.")
                        .font(.headline)
                    HStack {
                        Button("Reject") {
                            viewModel.rejectInvite()
                        }
                        .buttonStyle(.bordered)
                        
                        Button("Accept") {
                            viewModel.acceptInvite()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            
            if let roomId = viewModel.activeGameRoomId {
                Text("Game room: \(roomId)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            
            Text(viewModel.systemMessage)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .navigationTitle("Game Lobby")
//        .navigationBarTitleDisplayMode(.inline)
    }
}
