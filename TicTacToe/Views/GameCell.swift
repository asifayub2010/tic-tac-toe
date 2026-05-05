//
//  GameCell.swift
//  TicTacToe
//
//  Created by Asif Ayub on 27/04/2026.
//


import SwiftUI

struct GameCell: View {
    let player: Player?
    let size: CGFloat
    let action: () -> Void
    
    private var symbol: String {
        if let player = player {
            return player.symbol
        }
        return "·"
    }
    
    private var symbolColor: Color {
        guard let player = player else {
            return Color(white: 0.4)
        }
        switch player {
        case .x: return Color(red: 0.30, green: 0.62, blue: 0.88)
        case .o: return Color(red: 0.88, green: 0.33, blue: 0.33)
        case .y: return Color(red: 0.33, green: 0.88, blue: 0.55)
        }
    }
    
    private var backgroundColor: Color {
        Color(red: 0.09, green: 0.13, blue: 0.24) // #16213E
    }
    
    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(backgroundColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(red: 0.06, green: 0.20, blue: 0.38), lineWidth: 1)
                    )
                
                Text(symbol)
                    .font(.system(size: size * 0.5, weight: .bold, design: .rounded))
                    .foregroundColor(symbolColor)
                    .shadow(color: symbolColor.opacity(0.3), radius: 4, x: 0, y: 0)
            }
        }
        .frame(width: size, height: size)
        .disabled(player != nil)
    }
}