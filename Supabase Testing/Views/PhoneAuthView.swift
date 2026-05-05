//
//  PhoneAuthView.swift
//  Supabase Testing
//
//  Created by mac on 05/05/2026.
//


// PhoneAuthView.swift
import SwiftUI

struct PhoneAuthView: View {
    
    @State private var phoneNumber = "+92"      // Start with country code
    @State private var otpCode = ""
    @State private var isOTPSent = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showSuccess = false
    
    var body: some View {
        VStack(spacing: 30) {
            Text(isOTPSent ? "Enter OTP" : "Phone Login")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            VStack(spacing: 20) {
                if !isOTPSent {
                    TextField("Phone Number (+92345...)", text: $phoneNumber)
                        .textFieldStyle(.roundedBorder)
//                        .keyboardType(.phonePad)
                        .autocorrectionDisabled()
                } else {
                    TextField("6-digit OTP", text: $otpCode)
                        .textFieldStyle(.roundedBorder)
//                        .keyboardType(.numberPad)
                        .autocorrectionDisabled()
                }
            }
            .padding(.horizontal)
            
            if let error = errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
                    .multilineTextAlignment(.center)
            }
            
            Button {
                Task {
                    await handleAction()
                }
            } label: {
                Text(buttonTitle)
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(12)
            }
            .padding(.horizontal)
            .disabled(isLoading)
            
            if isOTPSent {
                Button("Resend OTP") {
                    Task { await resendOTP() }
                }
                .foregroundColor(.blue)
            }
            
            Spacer()
        }
        .padding()
        .alert("Success", isPresented: $showSuccess) {
            Button("Continue") {
                // Navigate to main app
            }
        } message: {
            Text("Logged in successfully!")
        }
    }
    
    private var buttonTitle: String {
        isLoading ? "Please wait..." : (isOTPSent ? "Verify OTP" : "Send OTP")
    }
    
    private func handleAction() async {
        isLoading = true
        errorMessage = nil
        
        do {
            if !isOTPSent {
                try await SupabaseAuthManager.shared.sendOTP(phone: phoneNumber)
                isOTPSent = true
            } else {
                let authResponse = try await SupabaseAuthManager.shared.verifyOTP(phone: phoneNumber, token: otpCode)
                print("✅ Login successful: \(authResponse.user?.email ?? "")")
                showSuccess = true
            }
        } catch let error as SupabaseError {
            errorMessage = error.message
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    private func resendOTP() async {
        isLoading = true
        errorMessage = nil
        do {
            try await SupabaseAuthManager.shared.sendOTP(phone: phoneNumber)
            // Optionally show a toast "OTP Resent"
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
