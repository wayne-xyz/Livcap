//
//  AboutView.swift
//  Livcap
//
//  About window showing app information, version, and important links
//

import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    
    private let appVersion = "1.1"
    private let privacyPolicyURL = "https://livcap.app/privacy"
    private let termsURL = "https://livcap.app/terms"
    private let githubURL = "https://github.com/wayne-xyz/Livcap"
    
    var body: some View {
        VStack(spacing: 20) {
            // Close button

            
            // App icon and title
            VStack(spacing: 12) {
                
                
                Text("Livcap")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Live Caption for macOS")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Text("Version \(appVersion)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)
            }
            .padding(.top, 20)
            
            Spacer()
            
            // Links section
            VStack(spacing: 16) {
                LinkRow(title: "Privacy Policy", url: privacyPolicyURL, icon: "lock.shield")
                LinkRow(title: "Terms of Service", url: termsURL, icon: "doc.text")
                LinkRow(title: "Issues & Feedback", url: githubURL, icon: "questionmark.circle")
            }
            .padding(.horizontal, 20)
            
            Spacer()
            
            // Footer
            Text("© 2025 Livcap. All rights reserved.")
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.bottom, 20)
        }
        .frame(width: 300, height: 400)
        .background(.ultraThinMaterial)

    }
}

struct LinkRow: View {
    let title: String
    let url: String
    let icon: String
    
    var body: some View {
        Link(destination: URL(string: url)!) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(.blue)
                    .frame(width: 20)
                
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primary)
                
                Spacer()
                
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.gray.opacity(0.05))
            .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
        .help("Open \(title)")
    }
}

#Preview("About View") {
    AboutView()
        .preferredColorScheme(.light)
}

#Preview("About View - Dark") {
    AboutView()
        .preferredColorScheme(.dark)
}
