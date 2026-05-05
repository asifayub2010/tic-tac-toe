//
//  SupabaseRealtimeClientViewModel.swift
//  Supabase Testing
//
//  Created by mac on 02/05/2026.
//


// ViewModels/GameViewModel.swift

import Foundation
import SwiftUI
import Combine

class SupabaseRealtimeClientViewModel: ObservableObject {
    // MARK: - Published Properties
    
    
    // MARK: - Private Properties
    private let realtimeClient: SupabaseRealtimeClient
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    init() {
        let config = SupabaseRealtimeConfig(url: "https://eilxfocmlnzsjkrgbvvv.supabase.co", apiKey: "sb_publishable_PhNhE083zZ3FMjOBbsxeXw_wMT6k8-o")
        realtimeClient = SupabaseRealtimeClient(config: config)
    }
    
    // MARK: - Public Methods
    func connect() {
        realtimeClient.connect()
    }
    
    func disconnect() {
        realtimeClient.disconnect()
    }
    
    func joinAChannelByPlayer1() {
        realtimeClient.joinChannel(channelId: "1234", username: "Player1")
    }
    
    func joinAChannelByPlayer2() {
        realtimeClient.joinChannel(channelId: "1234", username: "Player2")
    }
}
