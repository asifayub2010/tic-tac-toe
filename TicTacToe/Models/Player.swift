//
//  Player.swift
//  TicTacToe
//
//  Created by Asif Ayub on 27/04/2026.
//


import Foundation

enum Player: String, CaseIterable {
    case x = "X"
    case o = "O"
    case y = "Y"
    
    var symbol: String {
        switch self {
        case .x: return "✖️"
        case .o: return "◉"
        case .y: return "▲"
        }
    }
    
    var colorName: String {
        switch self {
        case .x: return "playerX"
        case .o: return "playerO"
        case .y: return "playerY"
        }
    }
    
    func defaultDisplayName(index: Int) -> String {
        switch self {
        case .x: return "Player 1"
        case .o: return "Player 2"
        case .y: return "Player 3"
        }
    }
}

enum GameResult: Equatable {
    case win(Player)
    case draw
    case none
}

struct GameMove {
    let row: Int
    let col: Int
    let player: Player
}

struct Score {
    var xWins: Int = 0
    var oWins: Int = 0
    var yWins: Int = 0
    var draws: Int = 0
}

enum GameMode: Equatable {
    case singlePlayer // vs AI
    case twoPlayerOffline
    case threePlayerOffline
    case twoPlayerOnline(roomId: String, isHost: Bool)
    case threePlayerOnline(roomId: String, isHost: Bool)
    
    var isOnline: Bool {
        switch self {
        case .twoPlayerOnline, .threePlayerOnline: return true
        default: return false
        }
    }
}
