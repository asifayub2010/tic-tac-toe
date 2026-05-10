//
//  GameBoardView.swift
//  TicTacToe
//
//  Created by Asif Ayub on 27/04/2026.
//


import SwiftUI

struct GameBoardView: View {
    @ObservedObject var viewModel: GameViewModelNew
    
    var body: some View {
        GeometryReader { geometry in
            let availableWidth = geometry.size.width - 24 // padding
            let availableHeight = geometry.size.height - 32 // padding
            let size = min(availableWidth, availableHeight)
            let cellSize = (size - CGFloat(viewModel.boardSize - 1) * 4) / CGFloat(viewModel.boardSize)
            
            VStack {
                Spacer()
                
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(cellSize), spacing: 4), count: viewModel.boardSize), spacing: 4) {
                    ForEach(0..<(viewModel.boardSize * viewModel.boardSize), id: \.self) { index in
                        let row = index / viewModel.boardSize
                        let col = index % viewModel.boardSize
                        
                        GameCell(
                            player: viewModel.board[row][col],
                            size: cellSize
                        ) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                viewModel.makeMove(at: row, column: col)
                            }
                        }
                    }
                }
                .frame(width: size, height: size)
                
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 16)
        .background(Color(red: 0.10, green: 0.10, blue: 0.18))
    }
}
