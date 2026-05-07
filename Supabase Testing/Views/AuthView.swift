//
//  AuthView.swift
//  Supabase Testing
//
//  Created by mac on 05/05/2026.
//


// Authentication service
import SwiftUI

struct AuthView: View {
    
    @State private var email = ""
    @State private var password = ""
    @State private var username = ""
    @State private var isLogin = true
    @State private var userLoginState = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showSuccess = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 30) {
                Text(isLogin ? "Welcome Back" : "Create Account")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                VStack(spacing: 20) {
                    TextField("Username", text: $username)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                    
                    TextField("Email", text: $email)
                        .textFieldStyle(.roundedBorder)
//                        .textInputAutocapitalization(.never)
//                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                    
                    SecureField("Password", text: $password)
                        .textFieldStyle(.roundedBorder)
                }
                .padding(.horizontal)
                
                if let error = errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                }
                
                Button {
                    Task {
                        await authenticate()
                    }
                } label: {
                    Text(isLogin ? "Sign In" : "Sign Up")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(12)
                }
                .padding(.horizontal)
                .disabled(isLoading)
                
                Button {
                    withAnimation {
                        isLogin.toggle()
                        errorMessage = nil
                    }
                } label: {
                    Text(isLogin ? "Don't have an account? Sign Up" : "Already have an account? Sign In")
                        .font(.footnote)
                }
                
                Spacer()
            }
            .navigationDestination(isPresented: $userLoginState) {
                GameStatusView(currentPlayerName: username)
            }
            .padding()
            .navigationTitle("Authentication")
            .onAppear {
                username = SupabaseAuthManager.shared.currentUsername
            }
            .alert("Success", isPresented: $showSuccess) {
                Button("OK") {
                    // Navigate to main app
                }
            } message: {
                Text(isLogin ? "Logged in successfully!" : "Account created successfully!")
            }
        }
    }
    
    private func authenticate() async {
        guard !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Please enter a username."
            return
        }
        
        guard !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Please enter your email."
            return
        }
        
        guard !password.isEmpty else {
            errorMessage = "Please enter your password."
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        do {
            if isLogin {
                _ = try await SupabaseAuthManager.shared.signIn(email: email, password: password)
                userLoginState = true
            } else {
                _ = try await SupabaseAuthManager.shared.signUp(email: email, password: password)
                userLoginState = true
            }
            SupabaseAuthManager.shared.saveUsername(username.trimmingCharacters(in: .whitespacesAndNewlines))
            showSuccess = true
        } catch let error as SupabaseError {
            errorMessage = error.message
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
}//SupabaseAuthManager.shared.isLoggedIn
