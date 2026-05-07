//
//  SupabaseAuthManager.swift
//  Supabase Testing
//
//  Created by mac on 05/05/2026.
//


// SupabaseAuthManager.swift
import Foundation

class SupabaseAuthManager {
    
    static let shared = SupabaseAuthManager()
    private init() {}
    
    // MARK: - Change these with your project details
    private let supabaseURL = "https://eilxfocmlnzsjkrgbvvv.supabase.co"
    private let anonKey = "sb_publishable_PhNhE083zZ3FMjOBbsxeXw_wMT6k8-o"
    
    private var headers: [String: String] {
        [
            "apikey": anonKey,
            "Content-Type": "application/json"
        ]
    }
    
    // MARK: - Sign Up
    func signUp(email: String, password: String) async throws -> AuthResponse {
        let url = URL(string: "\(supabaseURL)/auth/v1/signup")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = headers
        
        let body: [String: Any] = [
            "email": email,
            "password": password
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        return try handleAuthResponse(data: data, response: response)
    }
    
    // MARK: - Sign In
    func signIn(email: String, password: String) async throws -> AuthResponse {
        let url = URL(string: "\(supabaseURL)/auth/v1/token?grant_type=password")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = headers
        
        let body: [String: Any] = [
            "email": email,
            "password": password
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        return try handleAuthResponse(data: data, response: response)
    }
    
    // MARK: - Send OTP to Phone
    func sendOTP(phone: String) async throws {
        let url = URL(string: "\(supabaseURL)/auth/v1/otp")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = headers
        
        let body: [String: Any] = [
            "phone": phone,           // Must be in E.164 format: +923451111411
            "channel": "sms"          // or "whatsapp"
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        print(response)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            if let error = try? JSONDecoder().decode(SupabaseError.self, from: data) {
                throw error
            }
            throw NSError(domain: "SendOTPError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to send OTP"])
        }
    }
    
    // MARK: - Verify OTP
    func verifyOTP(phone: String, token: String) async throws -> AuthResponse {
        let url = URL(string: "\(supabaseURL)/auth/v1/verify")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = headers
        
        let body: [String: Any] = [
            "phone": phone,
            "token": token,
            "type": "sms"               // Important for phone verification
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        return try handleAuthResponse(data: data, response: response)
    }
    
    // MARK: - Sign Out
    func signOut() async throws {
        let url = URL(string: "\(supabaseURL)/auth/v1/logout")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = headers
        
        // Add access token if you have it (for better security)
        if let token = UserDefaults.standard.string(forKey: "access_token") {
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw NSError(domain: "SignOutError", code: 0)
        }
        
        clearSession()
    }
    
    private func handleAuthResponse(data: Data, response: URLResponse) throws -> AuthResponse {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "InvalidResponse", code: 0)
        }
        
        if httpResponse.statusCode == 200 || httpResponse.statusCode == 201 {
            let authResponse = try JSONDecoder().decode(AuthResponse.self, from: data)
            saveSession(authResponse)
            return authResponse
        } else {
            // Try to decode error
            if let error = try? JSONDecoder().decode(SupabaseError.self, from: data) {
                throw error
            } else {
                throw NSError(domain: "AuthError", code: httpResponse.statusCode)
            }
        }
    }
    
    // MARK: - Session Management
    private func saveSession(_ response: AuthResponse) {
        UserDefaults.standard.set(response.accessToken, forKey: "access_token")
        UserDefaults.standard.set(response.refreshToken, forKey: "refresh_token")
        UserDefaults.standard.set(response.user?.id, forKey: "user_id")
        UserDefaults.standard.set(response.user?.email, forKey: "user_email")
    }
    
    private func clearSession() {
        UserDefaults.standard.removeObject(forKey: "access_token")
        UserDefaults.standard.removeObject(forKey: "refresh_token")
        UserDefaults.standard.removeObject(forKey: "user_id")
        UserDefaults.standard.removeObject(forKey: "user_email")
    }
    
    var isLoggedIn: Bool {
        UserDefaults.standard.string(forKey: "access_token") != nil
    }
    
    var currentUsername: String {
        UserDefaults.standard.string(forKey: "player_username") ?? ""
    }
    
    func saveUsername(_ username: String) {
        UserDefaults.standard.set(username, forKey: "player_username")
    }
}
