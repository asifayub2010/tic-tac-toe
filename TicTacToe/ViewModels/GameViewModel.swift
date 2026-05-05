//
//  GameViewModel.swift
//  TicTacToe
//
//  Created by Asif Ayub on 27/04/2026.
//


import Foundation
import SwiftUI
import Combine

class GameViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published private(set) var board: [[Player?]] = []
    @Published private(set) var currentPlayer: Player = .x
    @Published private(set) var gameResult: GameResult = .none
    @Published private(set) var score = Score()
    @Published var showWinnerAlert = false
    @Published var winnerMessage = ""
    
    // MARK: - Configuration
    @Published var gameMode: GameMode = .twoPlayerOffline
    @Published var playerNames: [Player: String] = [
        .x: "Player 1",
        .o: "Player 2",
        .y: "Player 3"
    ]
    
    // MARK: - Private Properties
    private let winLength: Int
    private var gameActive = true
    private var lastWinner: Player? = nil
    private var cancellables = Set<AnyCancellable>()
    
    // Online Service
    private let realtimeService = SupabaseWebSocketService()
    private var myPlayerType: Player? // Which player I am in online mode
    
    // MARK: - Computed Properties
    var isGameOver: Bool {
        if case .none = gameResult {
            return false
        }
        return true
    }
    
    var boardSize: Int
    
    var turnText: String {
        if case .win(let winner) = gameResult {
            return "🏆 \(playerNames[winner] ?? winner.rawValue) Wins!"
        } else if case .draw = gameResult {
            return "🤝 Draw!"
        } else {
            let name = playerNames[currentPlayer] ?? currentPlayer.rawValue
            if gameMode.isOnline {
                return currentPlayer == myPlayerType ? "🎮 Your Turn (\(name))" : "⏳ Waiting for \(name)..."
            }
            return "🎮 \(name)'s Turn"
        }
    }
    
    var turnColor: Color {
        switch currentPlayer {
        case .x: return Color(red: 0.30, green: 0.62, blue: 0.88) // #4D9DE0
        case .o: return Color(red: 0.88, green: 0.33, blue: 0.33) // #E15554
        case .y: return Color(red: 0.33, green: 0.88, blue: 0.55) // #55E18B
        }
    }
    
    // MARK: - Initialization
    init(boardSize: Int = 9, winLength: Int = 5) {
        self.boardSize = boardSize
        self.winLength = winLength
        setupNotifications()
        resetGame()
    }
    
    private func setupNotifications() {
        NotificationCenter.default.publisher(for: .gameEventReceived)
            .compactMap { $0.userInfo?["message"] as? GameMessage }
            .sink { [weak self] message in
                self?.handleOnlineEvent(message)
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Public Methods
    func configureGame(mode: GameMode, names: [Player: String], myPlayer: Player? = nil) {
        self.gameMode = mode
        self.playerNames = names
        self.myPlayerType = myPlayer
        self.lastWinner = nil
        resetFullGame()
    }
    
    func resetGame() {
        board = Array(repeating: Array(repeating: nil, count: boardSize), count: boardSize)
        currentPlayer = lastWinner ?? .x
        gameActive = true
        gameResult = .none
        showWinnerAlert = false
        winnerMessage = ""
        
        // Handle AI start
        if gameMode == .singlePlayer && currentPlayer == .o {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.makeAIMove()
            }
        }
    }
    
    func resetFullGame() {
        lastWinner = nil
        resetGame()
        score = Score()
    }
    
    func makeMove(at row: Int, column: Int) {
        // Validate move
        guard gameActive,
              row >= 0, row < boardSize,
              column >= 0, column < boardSize,
              board[row][column] == nil else {
            return
        }
        
        // If online, only allow if it's my turn
        if gameMode.isOnline {
            guard currentPlayer == myPlayerType else { return }
            Task { await realtimeService.sendMove(row: row, col: column, player: currentPlayer.rawValue) }
//            // Broadcast the move
//            if case let .twoPlayerOnline(roomId, _) = gameMode {
//                Task { await realtimeService.sendMove(row: row, col: column, player: currentPlayer.rawValue) }
//            } else if case let .threePlayerOnline(roomId, _) = gameMode {
//                Task { await realtimeService.sendMove(roomId: roomId, player: currentPlayer.rawValue, row: row, col: column) }
//            }
        }
        
        processMove(row: row, col: column)
        
        // If single player and game still active, make AI move
        if gameMode == .singlePlayer && gameActive && currentPlayer == .o {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.makeAIMove()
            }
        }
    }
    
    func connect() async throws {
        try? await realtimeService.connect()
    }
    
    func disconnect() {
        realtimeService.disconnect()
    }
    
    // MARK: - Online Helpers
    func createRoom(mode: GameMode) async -> String? {
        let playerMode: GamePlayerMode = {
            if case .threePlayerOnline = mode { return .threePlayer }
            return .twoPlayer
        }()
        
        do {
            let roomId = try await realtimeService.createRoom(gamePlayerMode: playerMode)
            return roomId
        } catch {
            print("❌ Create room failed: \(error)")
            return nil
        }
    }
    
    func joinRoom(roomId: String, mode: GameMode) async {
        let playerMode: GamePlayerMode = {
            if case .threePlayerOnline = mode { return .threePlayer }
            return .twoPlayer
        }()
        
        try? await realtimeService.joinRoom(roomCode: roomId, gamePlayerMode: playerMode)
    }
    
    private func handleOnlineEvent(_ message: GameMessage) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            switch message.type {
            case .move:
                if let playerVal = message.data["player"],
                   let player = Player(rawValue: playerVal),
                   let row = Int(message.data["row"] ?? ""),
                   let col = Int(message.data["col"] ?? "") {
                    
                    // If it's not our move (already processed locally), process it
                    if player != self.myPlayerType {
                        self.processMove(row: row, col: col)
                    }
                }
            case .rematch:
                self.resetGame()
            default:
                break
            }
        }
    }
    
    // MARK: - Private Methods
    private func processMove(row: Int, col: Int) {
        // Place mark
        board[row][col] = currentPlayer
        
        // Check for win or draw
        if checkWin(row: row, col: col, player: currentPlayer) {
            gameActive = false
            gameResult = .win(currentPlayer)
            lastWinner = currentPlayer
            updateScore()
            winnerMessage = "🎉 \(playerNames[currentPlayer] ?? currentPlayer.rawValue) wins! 🎉"
            showWinnerAlert = true
        } else if checkDraw() {
            gameActive = false
            gameResult = .draw
            score.draws += 1
            winnerMessage = "🤝 It's a draw!"
            showWinnerAlert = true
        } else {
            nextPlayer()
        }
        
        if showWinnerAlert {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.showWinnerAlert = false
                if self?.gameResult != GameResult.none {
                    self?.resetGame()
                }
            }
        }
    }
    
    private func nextPlayer() {
        switch gameMode {
        case .singlePlayer, .twoPlayerOffline, .twoPlayerOnline:
            currentPlayer = currentPlayer == .x ? .o : .x
        case .threePlayerOffline, .threePlayerOnline:
            if currentPlayer == .x {
                currentPlayer = .o
            } else if currentPlayer == .o {
                currentPlayer = .y
            } else {
                currentPlayer = .x
            }
        }
    }
    
    private func makeAIMove() {
        var bestScore = -1
        var bestMoves: [(Int, Int)] = []
        
        for r in 0..<boardSize {
            for c in 0..<boardSize {
                if board[r][c] == nil {
                    let moveScore = evaluateMove(row: r, col: c, player: .o)
                    if moveScore > bestScore {
                        bestScore = moveScore
                        bestMoves = [(r, c)]
                    } else if moveScore == bestScore {
                        bestMoves.append((r, c))
                    }
                }
            }
        }
        
        if let randomBestMove = bestMoves.randomElement() {
            processMove(row: randomBestMove.0, col: randomBestMove.1)
        }
    }
    
    private func evaluateMove(row: Int, col: Int, player: Player) -> Int {
        let opponent: Player = .x
        if checkWinPotential(row: row, col: col, player: player, target: winLength) { return 100000 }
        if checkWinPotential(row: row, col: col, player: opponent, target: winLength) { return 50000 }
        if checkWinPotential(row: row, col: col, player: player, target: winLength - 1) { return 10000 }
        if checkWinPotential(row: row, col: col, player: opponent, target: winLength - 1) { return 5000 }
        
        var score = 0
        let directions = [(0, 1), (1, 0), (1, 1), (1, -1)]
        for (dx, dy) in directions {
            let playerCount = countConsecutive(row: row, col: col, dx: dx, dy: dy, player: player)
            let opponentCount = countConsecutive(row: row, col: col, dx: dx, dy: dy, player: opponent)
            score += playerCount * playerCount * 10
            score += opponentCount * opponentCount * 5
        }
        let center = Double(boardSize) / 2.0
        let distFromCenter = sqrt(pow(Double(row) - center, 2) + pow(Double(col) - center, 2))
        score += Int(10.0 - distFromCenter)
        return score
    }
    
    private func countConsecutive(row: Int, col: Int, dx: Int, dy: Int, player: Player) -> Int {
        var count = 0
        for step in 1..<winLength {
            let nr = row + dx * step
            let nc = col + dy * step
            if nr >= 0 && nr < boardSize && nc >= 0 && nc < boardSize && board[nr][nc] == player { count += 1 } else { break }
        }
        for step in 1..<winLength {
            let nr = row - dx * step
            let nc = col - dy * step
            if nr >= 0 && nr < boardSize && nc >= 0 && nc < boardSize && board[nr][nc] == player { count += 1 } else { break }
        }
        return count
    }
    
    private func checkWinPotential(row: Int, col: Int, player: Player, target: Int) -> Bool {
        let directions = [(0, 1), (1, 0), (1, 1), (1, -1)]
        for (dx, dy) in directions {
            if countConsecutive(row: row, col: col, dx: dx, dy: dy, player: player) >= target - 1 { return true }
        }
        return false
    }
    
    private func updateScore() {
        switch gameResult {
        case .win(let player):
            switch player {
            case .x: score.xWins += 1
            case .o: score.oWins += 1
            case .y: score.yWins += 1
            }
        default: break
        }
    }
    
    private func checkWin(row: Int, col: Int, player: Player) -> Bool {
        let directions = [(0, 1), (1, 0), (1, 1), (1, -1)]
        for (dx, dy) in directions {
            var count = 1
            for step in 1..<winLength {
                let nr = row + dx * step
                let nc = col + dy * step
                if nr < 0 || nr >= boardSize || nc < 0 || nc >= boardSize || board[nr][nc] != player { break }
                count += 1
            }
            for step in 1..<winLength {
                let nr = row - dx * step
                let nc = col - dy * step
                if nr < 0 || nr >= boardSize || nc < 0 || nc >= boardSize || board[nr][nc] != player { break }
                count += 1
            }
            if count >= winLength { return true }
        }
        return false
    }
    
    private func checkDraw() -> Bool {
        return !board.flatMap { $0 }.contains(nil)
    }
}
