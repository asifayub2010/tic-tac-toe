//
//  User.swift
//  Supabase Testing
//
//  Created by mac on 05/05/2026.
//
import Foundation

struct User: Codable {
    let id: String
    let email: String?
    let createdAt: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case email
        case createdAt = "created_at"
    }
}
