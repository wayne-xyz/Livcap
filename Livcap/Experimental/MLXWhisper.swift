//
//  MLXWhisper.swift
//  Livcap
//
//  Created by Rongwei Ji on 6/9/25.
//

// this is the arch of the whsiper model based on the mlx
// 3 components for the whole model inference on mlx-whisper: 1. model arhc, model file loader, inference code

//MLX Whisper.swift

import MLX
import MLXNN
import Foundation


class MLXWhisper{
    
    func static_MLX_fun(){
        let a = MLXArray([1,2,3])
        let b = MLXArray([4,5,6])
        
        let c = a + b
        
        let shape=c.shape
        let dtype=c.dtype
        print("cshapoe\(shape), cdtype\(dtype)")
    }

}
