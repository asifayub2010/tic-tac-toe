//
//  Supabase_TestingApp.swift
//  Supabase Testing
//
//  Created by mac on 02/05/2026.
//

import SwiftUI

@main
struct Supabase_TestingApp: App {
    var body: some Scene {
        WindowGroup {
//            if SupabaseAuthManager.shared.isLoggedIn {
//                GameStatusView()
//            } else {
                AuthView()
//                PhoneAuthView()
//            }
        }
    }
}
