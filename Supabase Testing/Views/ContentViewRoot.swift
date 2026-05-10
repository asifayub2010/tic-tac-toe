import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: GameViewModelNew
    @Binding var isGameStarted: Bool
    @State private var showResetConfirmation = false

    var body: some View {
        ZStack {
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
                HeaderView(viewModel: viewModel, onBack: { isGameStarted = false })
                ScoreboardView(viewModel: viewModel)
                    .padding(.horizontal)
                GameBoardView(viewModel: viewModel)
                    .padding(.bottom, 8)
                ResetButtonView { showResetConfirmation = true }
                    .padding(.bottom, 20)
            }
        }
        .alert("Game Over", isPresented: $viewModel.showWinnerAlert) {
            if viewModel.gameMode.isOnline {
                if viewModel.pendingRematchOfferFrom != nil {
                    Button("Accept") { viewModel.acceptRematchOffer() }
                    Button("Decline", role: .destructive) { viewModel.declineRematchOffer() }
                } else if viewModel.isAwaitingRematchResponse {
                    Button("Cancel & Exit", role: .destructive) { viewModel.exitToLobby() }
                } else if viewModel.canOfferRematchNow {
                    Button("Play Again") { viewModel.offerRematch() }
                    Button("Exit", role: .destructive) { viewModel.exitToLobby() }
                } else {
                    Button("Exit", role: .destructive) { viewModel.exitToLobby() }
                }
            } else {
                Button("New Game") { viewModel.resetGame() }
                Button("Full Reset") { viewModel.resetFullGame() }
            }
        } message: {
            Text(viewModel.winnerMessage)
        }
        .actionSheet(isPresented: $showResetConfirmation) {
            ActionSheet(
                title: Text("Reset Game"),
                message: Text("Reset current game or full stats?"),
                buttons: [
                    .default(Text("Reset Current Game")) { viewModel.resetGame() },
                    .destructive(Text("Reset Full Stats")) { viewModel.resetFullGame() },
                    .cancel()
                ]
            )
        }
        .onChange(of: viewModel.gameResult) { _ in
            if viewModel.gameMode.isOnline,
               case .draw = viewModel.gameResult,
//               viewModel.amCurrentPlayer,
               !viewModel.isAwaitingRematchResponse,
               viewModel.pendingRematchOfferFrom == nil {
                viewModel.offerRematch()
            }
        }
        .onChange(of: viewModel.shouldExitToLobby) { shouldExit in
            if shouldExit { isGameStarted = false }
        }
    }
}

#Preview {
    ContentView(viewModel: GameViewModelNew(), isGameStarted: .constant(true))
}
