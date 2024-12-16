//
//  main.swift
//  AssetWriter
//
//  Created by Mac-Mini on 2024/12/13.
//

import Foundation
import AVFoundation
import CoreVideo

print("Hello, World!")
class VideoInfo {
    var time: Int64 = 0
    var filePath: String = ""
}

let input = "/Users/mac-mini/Downloads/04.mp4"
let output = "/Users/mac-mini/output"
let asset = AVAsset(url: URL(fileURLWithPath: input))
let videoTrack = asset.tracks(withMediaType: AVMediaType.video).first!
let readerOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: [String(kCVPixelBufferPixelFormatTypeKey) :kCVPixelFormatType_32BGRA])
let reader = try AVAssetReader(asset: asset)
reader.add(readerOutput)
reader.timeRange = CMTimeRange(start: CMTime(value: 0, timescale: 1000000), end: CMTime(value: 20000000, timescale: 1000000))
reader.startReading()
var videoInfos = Array<VideoInfo>()
var height = 0
var width = 0
var bytesPerRow = 0
while (reader.status == .reading) {
    let buffer = readerOutput.copyNextSampleBuffer()
    if let pixelBuffer = buffer?.imageBuffer {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer)
        height = CVPixelBufferGetHeight(pixelBuffer)
        width = CVPixelBufferGetWidth(pixelBuffer)
        bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let size = CVPixelBufferGetDataSize(pixelBuffer)
        
        let data = Data(bytes: baseAddress!, count: size)
        let fm = FileManager.default
        if !fm.fileExists(atPath: output) {
            try fm.createDirectory(at: URL(fileURLWithPath: output), withIntermediateDirectories: true)
        }
        let time = 1000000 * buffer!.presentationTimeStamp.value / Int64(buffer!.presentationTimeStamp.timescale)
        let filePath = output + "/\(time)"
        try data.write(to: URL(fileURLWithPath: filePath))
        let info = VideoInfo()
        info.time = time
        info.filePath = filePath
        videoInfos.append(info)
        
        CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
    }
}

let outputURL = URL(fileURLWithPath: output + "/123.mp4")
try? FileManager.default.removeItem(at: outputURL)
let assetWriter = try AVAssetWriter(url: outputURL, fileType: AVFileType.mp4)

// 配置视频写入的设置
let videoSettings: [String: Any] = [
    AVVideoCodecKey: AVVideoCodecType.h264,
    AVVideoWidthKey: width,
    AVVideoHeightKey: height
]

// 创建 AVAssetWriterInput
let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
writerInput.expectsMediaDataInRealTime = false

// 创建 PixelBufferAdaptor
let attributes: [String: Any] = [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
    kCVPixelBufferWidthKey as String: width,
    kCVPixelBufferHeightKey as String: height
]
let pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: writerInput, sourcePixelBufferAttributes: attributes)

// 添加输入到 AVAssetWriter
if assetWriter.canAdd(writerInput) {
    assetWriter.add(writerInput)
}
// 开始写入
assetWriter.startWriting()
assetWriter.startSession(atSourceTime: .zero)

// 写入帧
let frameRate = 25
let queue = DispatchQueue(label: "video_writer_queue")
var frameCount = 0
var index = 0

func getData(index: Int)->(pixelbuffer: CVPixelBuffer?, time: CMTime)? {
    if index >= videoInfos.count {
        return nil
    }
    let filePath = videoInfos[videoInfos.count - 1 - index].filePath
    let info = videoInfos[index]
    let presentationTime = info.time
    let pixelBuffer = createPixelBuffer(filePath: filePath, size: CGSize(width: width, height: height))
    return (pixelBuffer, CMTime(value: presentationTime, timescale: 1000000))
}

writerInput.requestMediaDataWhenReady(on: queue) {
    while writerInput.isReadyForMoreMediaData {
        if var info = getData(index: index) {
            pixelBufferAdaptor.append(info.pixelbuffer!, withPresentationTime: info.time)
            index += 1
            info.pixelbuffer = nil
        } else {
            writerInput.markAsFinished()
            assetWriter.finishWriting {
                if assetWriter.status == .completed {
                    print("视频写入成功: \(outputURL)")
                } else {
                    print("视频写入失败: \(String(describing: assetWriter.error))")
                }
            }
        }
    }
    
}

while true {
    sleep(1)
}
// 辅助函数: 创建像素缓冲区
func createPixelBuffer(filePath: String, size: CGSize) -> CVPixelBuffer? {
    let attributes: [String: Any] = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
        kCVPixelBufferWidthKey as String: size.width,
        kCVPixelBufferHeightKey as String: size.height
    ]

    var pixelBuffer: CVPixelBuffer?
    CVPixelBufferCreate(kCFAllocatorDefault, Int(size.width), Int(size.height), kCVPixelFormatType_32BGRA, attributes as CFDictionary, &pixelBuffer)

    if let pixelBuffer = pixelBuffer {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer)
        if let data = try? Data(contentsOf: URL(fileURLWithPath: filePath)) {
            let pointer = UnsafeMutablePointer<UInt8>.allocate(capacity: data.count)
            data.copyBytes(to: pointer, count: data.count)
            baseAddress?.copyMemory(from: pointer, byteCount: data.count)
            pointer.deallocate()
        }
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
    }
    
    return pixelBuffer
}
