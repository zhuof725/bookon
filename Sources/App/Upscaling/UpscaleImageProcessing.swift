//
//  UpscaleImageProcessing.swift
//
//  移植自 Aidoku（https://github.com/Aidoku/Aidoku）Core/Upscaling/ImageProcessingModel.swift，GPLv3。
//

//
//  ImageModel.swift
//  Aidoku
//
//  Created by Skitty on 6/25/25.
//

import CoreML

protocol ImageProcessingModel {
    init?(model: MLModel, config: [String: Any])
    func process(_ image: CGImage) async -> CGImage?
}
