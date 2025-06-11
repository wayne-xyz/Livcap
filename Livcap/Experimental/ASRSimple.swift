//
//  SimpleView.swift
//  Livcap
//
//  Created by Rongwei Ji on 6/9/25.
//

import SwiftUI

struct ASRSimple: View {

    @State private var STT_Result = ""
    

    var body: some View {
        VStack(spacing: 20) {
            Text("ASR Simple Result: \(STT_Result)")
             Button("Test MLX") {
                let whisper = MLXWhisper()
                whisper.static_MLX_fun()
            }
        }
        .frame(width: 300, height: 400)
        .onAppear(){
            
        }
    }
    
    
    private func transcribe(){
        
    }
    
}

    
#Preview {
    ASRSimple()
}
