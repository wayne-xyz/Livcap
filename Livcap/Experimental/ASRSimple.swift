//
//  SimpleView.swift
//  Livcap
//
//  Created by Rongwei Ji on 6/9/25.
//

import SwiftUI

struct ASRSimpleView: View {

    @State private var STT_Result = ""
    

    var body: some View {
        VStack(spacing: 20) {
            Text("ASR Simple Result: \(STT_Result)")
             Button("Test MLX") {
                loadModel()
            }
        }
        .frame(width: 300, height: 400)
        .onAppear(){
            
        }
    }
    
    private func loadModel(){
        do{
            var model=try WhisperLoader.load(printLog: true)
            print("Model loaded successfully")
        }catch{
            print("Error loading model: \(error)")
        }
    }
    private func transcribe(){
        
    }
    
}

    
#Preview {
    ASRSimpleView()
}
