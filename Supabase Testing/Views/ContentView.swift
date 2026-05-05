//
//  ContentView.swift
//  Supabase Testing
//
//  Created by mac on 02/05/2026.
//

// ContentView.swift

import SwiftUI

struct ContentView: View {
    // Create separate clients for player 1 and player 2
//    @StateObject private var player1Client = RealtimeClient()
//    @StateObject private var player2Client = RealtimeClient()
//    @StateObject private var playerClient = SupabaseRealtimeClientViewModel()
    
    var body: some View {
        VStack(spacing: 0) {
            // Player 1 View
//            PlayerView(
//                playerName: "Player 1",
//                color: .blue,
//                viewModel: GameViewModel(
//                    playerName: "Player 1",
//                    realtimeClient: player1Client
//                )
//            )
            
//            Divider()
//                .background(Color.gray)
//                .frame(height: 2)
            
            // Player 2 View
//            PlayerView(
//                playerName: "Player 2",
//                color: .green,
//                viewModel: GameViewModel(
//                    playerName: "Player 2",
//                    realtimeClient: player2Client
//                )
//            )
        }
        .background(Color.black.opacity(0.05))
        .onAppear {
            
        }
    }
}

//struct PlayerView: View {
//    let playerName: String
//    let color: Color
//    @StateObject var viewModel: GameViewModel
//    
//    var body: some View {
//        VStack(spacing: 20) {
//            // Header with player name and status
//            HStack {
//                Text(playerName)
//                    .font(.title)
//                    .fontWeight(.bold)
//                    .foregroundColor(color)
//                
//                Spacer()
//                
//                // Connection status indicator
//                HStack {
//                    Circle()
//                        .fill(viewModel.isConnected ? Color.green : Color.red)
//                        .frame(width: 10, height: 10)
//                    Text(viewModel.connectionStatus)
//                        .font(.caption)
//                        .foregroundColor(.gray)
//                }
//            }
//            .padding(.horizontal)
//            
//            // Room ID display/input
//            HStack {
//                if viewModel.isInRoom {
//                    Text("Room: \(viewModel.roomId)")
//                        .font(.headline)
//                        .foregroundColor(.blue)
//                } else {
//                    TextField("Enter Room ID", text: $viewModel.roomId)
//                        .textFieldStyle(RoundedBorderTextFieldStyle())
////                        .autocapitalization(.allCharacters)
//                        .frame(maxWidth: .infinity)
//                }
//            }
//            .padding(.horizontal)
//            
//            // Control buttons
//            HStack(spacing: 15) {
//                // Connect/Disconnect button
//                Button(action: {
//                    if viewModel.isConnected {
//                        Task { await viewModel.disconnect()}
//                    } else {
//                        Task { await viewModel.connect() }
//                    }
//                }) {
//                    HStack {
//                        Image(systemName: viewModel.isConnected ? "antenna.radiowaves.left.and.right.slash" : "antenna.radiowaves.left.and.right")
//                        Text(viewModel.isConnected ? "Disconnect" : "Connect")
//                    }
//                    .frame(maxWidth: .infinity)
//                    .padding()
//                    .background(viewModel.isConnected ? Color.red : Color.green)
//                    .foregroundColor(.white)
//                    .cornerRadius(10)
//                }
//                
//                // Join/Leave button
//                Button(action: {
//                    if viewModel.isInRoom {
//                        Task { await viewModel.leaveRoom() }
//                    } else {
//                        Task { await viewModel.joinRoom() }
//                    }
//                }) {
//                    HStack {
//                        Image(systemName: viewModel.isInRoom ? "rectangle.portrait.and.arrow.right" : "rectangle.portrait.and.arrow.right.fill")
//                        Text(viewModel.isInRoom ? "Leave" : "Join")
//                    }
//                    .frame(maxWidth: .infinity)
//                    .padding()
//                    .background(viewModel.isInRoom ? Color.orange : Color.blue)
//                    .foregroundColor(.white)
//                    .cornerRadius(10)
//                }
//                .disabled(!viewModel.isConnected)
//            }
//            .padding(.horizontal)
//            
//            // Message input and send
//            HStack {
//                TextField("Enter message", text: $viewModel.messageText)
//                    .textFieldStyle(RoundedBorderTextFieldStyle())
//                    .disabled(!viewModel.isInRoom)
//                
//                Button(action: viewModel.sendMessage) {
//                    Image(systemName: "paperplane.fill")
//                        .foregroundColor(viewModel.isInRoom ? color : .gray)
//                }
//                .disabled(!viewModel.isInRoom || viewModel.messageText.isEmpty)
//            }
//            .padding(.horizontal)
//            
//            // Messages display
//            VStack(alignment: .leading, spacing: 8) {
//                Text("Messages")
//                    .font(.headline)
//                    .padding(.horizontal)
//                
//                ScrollView {
//                    VStack(alignment: .leading, spacing: 5) {
//                        ForEach(viewModel.messages.indices, id: \.self) { index in
//                            Text(viewModel.messages[index])
//                                .font(.caption)
//                                .padding(.horizontal)
//                                .padding(.vertical, 4)
//                                .background(viewModel.messages[index].hasPrefix("Me:") ? color.opacity(0.1) : Color.gray.opacity(0.1))
//                                .cornerRadius(5)
//                        }
//                    }
//                }
//                .frame(maxHeight: 150)
//                .background(Color.gray.opacity(0.05))
//                .cornerRadius(10)
//                .padding(.horizontal)
//            }
//        }
//        .padding(.vertical)
//        .background(Color.white)
//    }
//}
