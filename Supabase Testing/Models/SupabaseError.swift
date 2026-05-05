//
//  SupabaseError.swift
//  Supabase Testing
//
//  Created by mac on 05/05/2026.
//
import Foundation

struct SupabaseError: Codable, LocalizedError {
    let code: String?
    let message: String
    
    var errorDescription: String? { message }
}
