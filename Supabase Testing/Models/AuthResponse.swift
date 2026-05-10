//
//  AuthResponse.swift
//  Supabase Testing
//
//  Created by mac on 05/05/2026.
//
import Foundation

// AuthModels.swift
struct AuthResponse: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
    let user: User?
    
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case user
    }
}

//if game draw then current player will make move and broadcast score messsage and send offer to play again. When user decline the offer to play again then it should leave that channel also and broadcast decline message before leaving the channel. Also when anyplayer leaves the room the other player will become winner. and alert him you won and go back to select new player to offer for new game play.
