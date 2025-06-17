//
//  SimpleView.swift
//  Livcap
//
//  Created by Rongwei Ji on 6/9/25.
//

import SwiftUI

struct ASRSimpleView: View {
    @StateObject private var viewModel = ASRSimpleViewModel()
    @State private var selectedSample = "Speaker26_000"
    
    var body: some View {
        VStack(spacing: 20) {
            // Status and Info Section
            VStack(alignment: .leading, spacing: 10) {
                Text("Status: \(viewModel.statusMessage)")
                    .font(.headline)
                
                if viewModel.audioDuration > 0 {
                    Text("Audio Duration: \(String(format: "%.2f", viewModel.audioDuration))s")
                        .font(.subheadline)
                }
                
                if viewModel.transcriptionTime > 0 {
                    Text("Transcription Time: \(String(format: "%.2f", viewModel.transcriptionTime))s")
                        .font(.subheadline)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(10)
            
            // Sample Selection
            Picker("Select Sample", selection: $selectedSample) {
                Text("Sample 1").tag("Speaker26_000")
                Text("Sample 2").tag("Speaker27_000")
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(.horizontal)
            
            // Transcription Result
            ScrollView {
                Text(viewModel.transcribedText)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(10)
            }
            .frame(height: 200)
            
            // Transcribe Button
            Button(action: {
                Task {
                    await viewModel.sftranscribeSample(sampleName: selectedSample)
                }
            }) {
                Text("Transcribe Sample")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(viewModel.canTranscribe ? Color.blue : Color.gray)
                    .cornerRadius(10)
            }
            .disabled(!viewModel.canTranscribe)
        }
        .padding()
        .frame(width: 400, height: 500)
    }
}

#Preview {
    ASRSimpleView()
}
