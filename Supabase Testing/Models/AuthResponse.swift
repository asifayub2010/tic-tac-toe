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
