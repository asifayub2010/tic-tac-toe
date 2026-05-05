//
//  ContentView 2.swift
//  Supabase Testing
//
//  Created by mac on 05/05/2026.
//


import SwiftUI

struct GameStatusView: View {
    @StateObject var viewModel = GameViewModel()
    @State private var playerName: String = ""
    @State private var players: [String] = ["Player1", "Player2"]
    @State private var lastMessage: String = "No message yet"
    @State private var xMove: String = "\(Int.random(in: 0...8))"
    @State private var yMove: String = "\(Int.random(in: 0...8))"

    var body: some View {
        VStack {
            HStack {
                TextField("Enter name", text: $viewModel.playerName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())

                Button(viewModel.connectionStatus) {
                    if viewModel.isConnected {
                        viewModel.disconnect()
                    } else {
                        viewModel.connect()
                    }
                }
            }
            .padding()

            Divider()

            ForEach(viewModel.users, id: \.self) { player in
                Text("-----\(player)-----")
            }

            Divider()

            Text(viewModel.messageText)
                .padding()
            Divider()
            HStack {
                VStack {
                    TextField("X Move", text: $xMove)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    
                    TextField("Y Move", text: $yMove)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }

                Button("Play Move") {
                    viewModel.sendMessage(x: xMove, y: yMove)
                    xMove = "\(Int.random(in: 0...8))"
                    yMove = "\(Int.random(in: 0...8))"
                }
            }
        }
        .padding()
    }
}
