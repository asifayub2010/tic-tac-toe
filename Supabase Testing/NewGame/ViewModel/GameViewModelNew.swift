//
//  GameViewModelNew.swift
//  TicTacToe
//
//  Created by Asif Ayub on 27/04/2026.
//


import Foundation
import SwiftUI
import Combine

class GameViewModelNew: ObservableObject {
    // MARK: - Published Properties
    @Published private(set) var board: [[Player?]] = []
    @Published private(set) var currentPlayer: Player = .x
    @Published private(set) var gameResult: GameResult = .none
    @Published private(set) var score = Score()
    @Published var showWinnerAlert = false
    @Published var winnerMessage = ""
    
    // MARK: - Online Properties
    @Published var isAwaitingRematchResponse = false
    @Published var pendingRematchOfferFrom: String? = nil
    @Published var shouldExitToLobby = false

    private var realtimeClient: SupabaseRealtimeClient?
    private var roomId: String?
    private var isLeavingChannel = false
    
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
//    private let realtimeService = SupabaseWebSocketService()
    var myPlayerType: Player? // Which player I am in online mode
    
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
//        setupNotifications()
        resetGame()
    }
    
//    private func setupNotifications() {
//        NotificationCenter.default.publisher(for: .gameEventReceived)
//            .compactMap { $0.userInfo?["message"] as? GameMessage }
//            .sink { [weak self] message in
//                self?.handleOnlineEvent(message)
//            }
//            .store(in: &cancellables)
//    }
    
    // MARK: - Public Methods
    
    func configureOnline(roomId: String, myPlayer: Player, names: [Player: String], client: SupabaseRealtimeClient) {
        self.gameMode = .twoPlayerOnline(roomId: roomId, isHost: myPlayer == .x)
        self.playerNames = names
        self.myPlayerType = myPlayer
        self.realtimeClient = client
        self.roomId = roomId
        client.delegate = self
        // Join channel if not already joined by the lobby
        client.joinChannel(channelId: roomId, username: names[myPlayer] ?? myPlayer.rawValue)
        resetFullGame()
    }
    
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
        isAwaitingRematchResponse = false
        pendingRematchOfferFrom = nil
        
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
        
        // Online: only allow if it's my turn
        if gameMode.isOnline {
            guard currentPlayer == myPlayerType else { return }
        }
        
//        // If online, only allow if it's my turn
//        if gameMode.isOnline {
//            guard currentPlayer == myPlayerType else { return }
//            Task { await realtimeService.sendMove(row: row, col: column, player: currentPlayer.rawValue) }
////            // Broadcast the move
////            if case let .twoPlayerOnline(roomId, _) = gameMode {
////                Task { await realtimeService.sendMove(row: row, col: column, player: currentPlayer.rawValue) }
////            } else if case let .threePlayerOnline(roomId, _) = gameMode {
////                Task { await realtimeService.sendMove(roomId: roomId, player: currentPlayer.rawValue, row: row, col: column) }
////            }
//        }
        
        processMove(row: row, col: column)
        
        // If single player and game still active, make AI move
        if gameMode == .singlePlayer && gameActive && currentPlayer == .o {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.makeAIMove()
            }
        }
    }
    
//    // MARK: - Online Helpers
//    func createRoom(mode: GameMode) async -> String? {
//        do {
//            let roomId = try await realtimeService.createRoom()
//            return roomId
//        } catch {
//            return nil
//        }
//    }
//    
//    func joinRoom(roomId: String) async {
//        try? await realtimeService.joinRoom(roomCode: roomId)
//    }
//    
//    private func handleOnlineEvent(_ message: GameMessage) {
//        DispatchQueue.main.async { [weak self] in
//            guard let self = self else { return }
//            
//            switch message.type {
//            case .move:
//                if let playerVal = message.data["player"],
//                   let player = Player(rawValue: playerVal),
//                   let row = Int(message.data["row"] ?? ""),
//                   let col = Int(message.data["col"] ?? "") {
//                    
//                    // If it's not our move (already processed locally), process it
//                    if player != self.myPlayerType {
//                        self.processMove(row: row, col: col)
//                    }
//                }
//            case .rematch:
//                self.resetGame()
//            default:
//                break
//            }
//        }
//    }
    
    // MARK: - Private Methods
    private func processMove(row: Int, col: Int) {
        // Place mark
        board[row][col] = currentPlayer
        
        // Broadcast the move if online (fire-and-forget)
        if gameMode.isOnline, let roomId, let client = realtimeClient {
            client.broadcastMove(channelId: roomId, player: currentPlayer.rawValue, x: String(row), y: String(col))
        }
        
        // Check for win or draw
        if checkWin(row: row, col: col, player: currentPlayer) {
            gameActive = false
            gameResult = .win(currentPlayer)
            lastWinner = currentPlayer
            updateScore()
            winnerMessage = "🎉 \(playerNames[currentPlayer] ?? currentPlayer.rawValue) wins! 🎉"
            showWinnerAlert = true
            
            if gameMode.isOnline, let roomId, let client = realtimeClient {
                // Broadcast score update and game over
                client.broadcast(channelId: roomId, event: "score_update", payload: [
                    "xWins": score.xWins,
                    "oWins": score.oWins,
                    "yWins": score.yWins,
                    "draws": score.draws,
                    "lastWinner": currentPlayer.rawValue,
                    "gameResult": "win"
                ])
                client.broadcast(channelId: roomId, event: "game_over", payload: [
                    "winner": currentPlayer.rawValue,
                    "reason": "win"
                ])
            }
        } else if checkDraw() {
            gameActive = false
            gameResult = .draw
            score.draws += 1
            winnerMessage = "🤝 It's a draw!"
            showWinnerAlert = true
            
            if gameMode.isOnline, let roomId, let client = realtimeClient {
                client.broadcast(channelId: roomId, event: "score_update", payload: [
                    "xWins": score.xWins,
                    "oWins": score.oWins,
                    "yWins": score.yWins,
                    "draws": score.draws,
                    "lastWinner": "",
                    "gameResult": "draw"
                ])
                client.broadcast(channelId: roomId, event: "game_over", payload: [
                    "winner": NSNull(),
                    "reason": "draw"
                ])
            }
        } else {
            nextPlayer()
        }
        
        if showWinnerAlert && !gameMode.isOnline {
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
    
    // MARK: - Online Rematch Helpers
    var canOfferRematchNow: Bool {
        guard gameMode.isOnline, let me = myPlayerType else { return false }
        switch gameResult {
        case .win(let winner):
            return winner == me
        case .draw:
            // For draw, the current player will start next game
            return currentPlayer == me
        case .none:
            return false
        }
    }

    func offerRematch() {
        guard gameMode.isOnline, let roomId, let client = realtimeClient else { return }
        isAwaitingRematchResponse = true
        let fromName = playerNames[myPlayerType ?? .x] ?? (myPlayerType?.rawValue ?? "Me")
        client.broadcast(channelId: roomId, event: "rematch_offer", payload: [
            "from": fromName
        ])
    }

    func acceptRematchOffer() {
        guard gameMode.isOnline, let roomId, let client = realtimeClient else { return }
        pendingRematchOfferFrom = nil
        client.broadcast(channelId: roomId, event: "rematch_response", payload: [
            "from": playerNames[myPlayerType ?? .x] ?? (myPlayerType?.rawValue ?? "Me"),
            "accepted": true
        ])
    }

    func declineRematchOffer() {
        guard gameMode.isOnline, let roomId, let client = realtimeClient else { return }
        pendingRematchOfferFrom = nil
        client.broadcast(channelId: roomId, event: "rematch_response", payload: [
            "from": playerNames[myPlayerType ?? .x] ?? (myPlayerType?.rawValue ?? "Me"),
            "accepted": false
        ])
        leaveChannelAndExit()
    }

    func exitToLobby() {
        guard gameMode.isOnline, let roomId, let client = realtimeClient else {
            shouldExitToLobby = true
            return
        }
        client.broadcast(channelId: roomId, event: "rematch_response", payload: [
            "from": playerNames[myPlayerType ?? .x] ?? (myPlayerType?.rawValue ?? "Me"),
            "accepted": false,
            "reason": "exit"
        ])
        leaveChannelAndExit()
    }

    private func leaveChannelAndExit() {
        isLeavingChannel = true
        if let roomId, let client = realtimeClient {
            client.leaveChannel(channelId: roomId)
        }
        shouldExitToLobby = true
    }

    private func handleAcceptedRematch() {
        // If we were the offerer, start a new game
        guard gameMode.isOnline, let roomId, let client = realtimeClient else { return }
        guard isAwaitingRematchResponse else { return }
        var first: Player?
        switch gameResult {
        case .win(let winner):
            first = winner
        case .draw:
            first = currentPlayer
        case .none:
            first = nil
        }
        if let firstPlayer = first {
            client.broadcast(channelId: roomId, event: "new_game_start", payload: [
                "firstPlayer": firstPlayer.rawValue
            ])
        }
        isAwaitingRematchResponse = false
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
extension GameViewModelNew: SupabaseRealtimeClientDelegate {
    func client(_ client: SupabaseRealtimeClient, didChangeState state: ConnectionState) { }

    func client(_ client: SupabaseRealtimeClient, channel: String, didReceivePresenceState users: [PresenceUser]) { }

    func client(_ client: SupabaseRealtimeClient, didReceivePresenceDiff diff: PresenceDiff) {
        // If opponent leaves, declare current user the winner and exit
        guard gameMode.isOnline, !isLeavingChannel else { return }
        if !diff.leaves.isEmpty {
            if let me = myPlayerType {
                gameActive = false
                gameResult = .win(me)
                lastWinner = me
                updateScore()
                winnerMessage = "Opponent left the room. You win by default!"
                showWinnerAlert = true
                // Leave channel and exit after showing alert briefly
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                    self?.leaveChannelAndExit()
                }
            }
        }
    }

    func client(_ client: SupabaseRealtimeClient, didReceiveMessage message: [String : Any]) {
        // Expect broadcast envelope: payload = { type: broadcast, event: "...", payload: {...} }
        guard let outer = message["payload"] as? [String: Any],
              let event = outer["event"] as? String,
              let data = outer["payload"] as? [String: Any] else { return }

        switch event {
        case "move":
            guard let px = data["player"] as? String,
                  let rx = data["x"] as? String,
                  let ry = data["y"] as? String,
                  let player = Player(rawValue: px),
                  let row = Int(rx), let col = Int(ry) else { return }
            // Only process opponent moves (avoid double apply)
            if player != myPlayerType {
                // Guard if already filled (idempotent)
                if row >= 0 && row < boardSize && col >= 0 && col < boardSize && board[row][col] == nil {
                    processMove(row: row, col: col)
                }
            }

        case "score_update":
            let xWins = data["xWins"] as? Int ?? score.xWins
            let oWins = data["oWins"] as? Int ?? score.oWins
            let yWins = data["yWins"] as? Int ?? score.yWins
            let draws = data["draws"] as? Int ?? score.draws
            score = Score(xWins: xWins, oWins: oWins, yWins: yWins, draws: draws)

        case "game_over":
            let reason = data["reason"] as? String ?? ""
            if reason == "win", let w = data["winner"] as? String, let winner = Player(rawValue: w) {
                gameActive = false
                gameResult = .win(winner)
                lastWinner = winner
                winnerMessage = "🎉 \(playerNames[winner] ?? winner.rawValue) wins! 🎉"
                showWinnerAlert = true
            } else if reason == "draw" {
                gameActive = false
                gameResult = .draw
                winnerMessage = "🤝 It's a draw!"
                showWinnerAlert = true
            }

        case "rematch_offer":
            if let from = data["from"] as? String {
                pendingRematchOfferFrom = from
                showWinnerAlert = true
                winnerMessage = "\(from) invited you to play again."
            }

        case "rematch_response":
            let accepted = data["accepted"] as? Bool ?? false
            if accepted {
                handleAcceptedRematch()
            } else {
                // Opponent declined — exit
                leaveChannelAndExit()
            }

        case "new_game_start":
            if let fp = data["firstPlayer"] as? String, let first = Player(rawValue: fp) {
                lastWinner = first
                showWinnerAlert = false
                gameResult = .none
                resetGame()
            }

        default:
            break
        }
    }

    func client(_ client: SupabaseRealtimeClient, didFailWithError error: any Error) { }
}

