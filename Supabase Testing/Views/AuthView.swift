//
//  AuthView.swift
//  Supabase Testing
//
//  Created by mac on 05/05/2026.
//


// AuthView.swift
import SwiftUI

struct AuthView: View {
    
    @State private var email = ""
    @State private var password = ""
    @State private var isLogin = true
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
            .padding()
            .navigationTitle("Authentication")
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
        isLoading = true
        errorMessage = nil
        
        do {
            if isLogin {
                _ = try await SupabaseAuthManager.shared.signIn(email: email, password: password)
            } else {
                _ = try await SupabaseAuthManager.shared.signUp(email: email, password: password)
            }
            
            NavigationLink("Go to Detail") {
                               ContentView()
                           }
            
            showSuccess = true
        } catch let error as SupabaseError {
            errorMessage = error.message
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
}//SupabaseAuthManager.shared.isLoggedIn
