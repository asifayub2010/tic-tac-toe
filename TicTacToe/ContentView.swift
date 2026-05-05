import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = GameViewModel()
    @State private var showResetConfirmation = false
    @State private var isGameStarted = false
    
    var body: some View {
        Group {
            if isGameStarted {
                gameView
            } else {
                SettingsView(viewModel: viewModel, isGameStarted: $isGameStarted)
            }
        }
    }
    
    private var gameView: some View {
        ZStack {
            // Background
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.10, green: 0.10, blue: 0.18),
                    Color(red: 0.06, green: 0.08, blue: 0.12)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 16) {
                // Header
                HeaderView(viewModel: viewModel, onBack: {
                    isGameStarted = false
                })
                
                // Scoreboard
                ScoreboardView(viewModel: viewModel)
                    .padding(.horizontal)
                
                // Game Board
                GameBoardView(viewModel: viewModel)
                    .padding(.bottom, 8)
                
                // Reset Button
                ResetButtonView {
                    showResetConfirmation = true
                }
                .padding(.bottom, 20)
            }
        }
        .alert("Game Over", isPresented: $viewModel.showWinnerAlert) {
            Button("New Game") {
                viewModel.resetGame()
            }
            Button("Full Reset") {
                viewModel.resetFullGame()
            }
        } message: {
            Text(viewModel.winnerMessage)
        }
        .actionSheet(isPresented: $showResetConfirmation) {
            ActionSheet(
                title: Text("Reset Game"),
                message: Text("Reset current game or full stats?"),
                buttons: [
                    .default(Text("Reset Current Game")) {
                        viewModel.resetGame()
                    },
                    .destructive(Text("Reset Full Stats")) {
                        viewModel.resetFullGame()
                    },
                    .cancel()
                ]
            )
        }
    }
}

// MARK: - Header View
struct HeaderView: View {
    @ObservedObject var viewModel: GameViewModel
    var onBack: () -> Void
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .foregroundColor(.white)
                        .padding(10)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Circle())
                }
                Spacer()
                VStack(spacing: 4) {
                    Text("9×9 Tic-Tac-Toe")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    
                    if case let .twoPlayerOnline(roomId, _) = viewModel.gameMode {
                        Text("Room ID: \(roomId)")
                            .font(.caption)
                            .foregroundColor(.blue)
                            .onTapGesture {
                                UIPasteboard.general.string = roomId
                            }
                    } else if case let .threePlayerOnline(roomId, _) = viewModel.gameMode {
                        Text("Room ID: \(roomId)")
                            .font(.caption)
                            .foregroundColor(.blue)
                            .onTapGesture {
                                UIPasteboard.general.string = roomId
                            }
                    }
                }
                Spacer()
                Circle().fill(Color.clear).frame(width: 40)
            }
            .padding(.horizontal)
            
            HStack(spacing: 12) {
                Circle()
                    .fill(viewModel.turnColor)
                    .frame(width: 12, height: 12)
                
                Text(viewModel.turnText)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.9))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(Color(red: 0.15, green: 0.18, blue: 0.28))
            .cornerRadius(40)
            .overlay(
                RoundedRectangle(cornerRadius: 40)
                    .stroke(viewModel.turnColor.opacity(0.5), lineWidth: 1)
            )
        }
        .padding(.top, 12)
    }
}

// MARK: - Reset Button View
struct ResetButtonView: View {
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 20, weight: .semibold))
                Text("New Game")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
            }
            .foregroundColor(Color(red: 0.10, green: 0.10, blue: 0.18))
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 1.0, green: 0.62, blue: 0.11),
                        Color(red: 1.0, green: 0.55, blue: 0.00)
                    ]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .cornerRadius(27)
            .shadow(color: Color(red: 1.0, green: 0.62, blue: 0.11).opacity(0.3), radius: 8, x: 0, y: 4)
        }
        .padding(.horizontal, 32)
    }
}

#Preview {
    ContentView()
}
