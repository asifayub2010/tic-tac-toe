//
//  ScoreboardView.swift
//  TicTacToe
//
//  Created by Asif Ayub on 27/04/2026.
//


import SwiftUI

struct ScoreboardView: View {
    @ObservedObject var viewModel: GameViewModelNew

    var body: some View {
        HStack(spacing: 20) {
            // Player X Score
            ScoreCard(
                playerName: viewModel.playerNames[.x] ?? "P1",
                wins: viewModel.score.xWins,
                color: Color(red: 0.30, green: 0.62, blue: 0.88),
                icon: "✖️",
                isActive: viewModel.currentPlayer == .x
            )

            // Player O Score
            ScoreCard(
                playerName: viewModel.playerNames[.o] ?? "P2",
                wins: viewModel.score.oWins,
                color: Color(red: 0.88, green: 0.33, blue: 0.33),
                icon: "◉",
                isActive: viewModel.currentPlayer == .o
            )

            if viewModel.gameMode == .threePlayerOffline ||
               ( {
                    if case .twoPlayerOnline = viewModel.gameMode { return true }
                    return false
                 }() ) {
                // Player Y Score
                ScoreCard(
                    playerName: viewModel.playerNames[.y] ?? "P3",
                    wins: viewModel.score.yWins,
                    color: Color(red: 0.33, green: 0.88, blue: 0.55),
                    icon: "▲",
                    isActive: viewModel.currentPlayer == .y
                )
            }

            // Draws
            VStack(spacing: 4) {
                Text("Draws")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.6))
                Text("\(viewModel.score.draws)")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(red: 0.09, green: 0.13, blue: 0.24))
        .cornerRadius(20)
    }
}

struct ScoreCard: View {
    let playerName: String
    let wins: Int
    let color: Color
    let icon: String
    let isActive: Bool

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Text(icon)
                    .font(.caption2)
                Text(playerName)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .lineLimit(1)
            }
            .foregroundColor(isActive ? .white : color)

            Text("\(wins)")
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .background(isActive ? color.opacity(0.3) : Color.clear)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isActive ? color : Color.clear, lineWidth: 1)
        )
    }
}
