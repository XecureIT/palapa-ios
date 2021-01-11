//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import Accelerate
import AVFoundation

@objc
public protocol AudioWaveformSamplingObserver: class {
    func audioWaveformDidFinishSampling(_ audioWaveform: AudioWaveform)
}

@objc
public class AudioWaveform: NSObject {
    @objc
    public var isSamplingComplete: Bool {
        return decibelSamples != nil
    }

    @objc
    public init?(asset: AVAsset) {
        guard CMTimeGetSeconds(asset.duration) <= AudioWaveform.maximumDuration else {
            return nil
        }

        super.init()

        beginSampling(for: asset)
    }

    deinit {
        sampleOperation?.cancel()
    }

    // MARK: - Caching

    @objc
    public init(contentsOfFile filePath: String) throws {
        guard let unarchivedSamples = NSKeyedUnarchiver.unarchiveObject(withFile: filePath) as? [Float] else {
            throw OWSAssertionError("Failed to unarchive decibel samples")
        }
        decibelSamples = unarchivedSamples
    }

    @objc
    public func write(toFile filePath: String, atomically: Bool) throws {
        guard isSamplingComplete, let decibelSamples = decibelSamples else {
            throw OWSAssertionError("can't write incomplete waveform to file \(filePath)")
        }

        let archivedData = NSKeyedArchiver.archivedData(withRootObject: decibelSamples)
        try archivedData.write(to: URL(fileURLWithPath: filePath), options: atomically ? .atomicWrite : .init())
    }

    // MARK: -

    @objc
    public func normalizedLevelsToDisplay(sampleCount: Int) -> [Float]? {
        guard isSamplingComplete else { return nil }

        // Do nothing if the number of requested samples is less than 1
        guard sampleCount > 0 else { return [] }

        // Do nothing if we don't yet have any samples.
        guard let decibelSamples = decibelSamples else {
            owsFailDebug("unexepctedly missing sample data")
            return nil
        }

        // If we're trying to downsample to less samples than exist, just return what we have
        guard decibelSamples.count > sampleCount else {
            return decibelSamples.map { 1 - ($0 / AudioWaveform.silenceDecibelThreshold) }
        }

        let downSampledData = downsample(samples: decibelSamples, toSampleCount: sampleCount)

        // Normalize to a range of 0-1 with 0 being silence.
        return downSampledData.map { 1 - ($0 / AudioWaveform.silenceDecibelThreshold) }
    }

    // MARK: - Sampling

    /// The recorded samples for this waveform.
    private var decibelSamples: [Float]?

    /// Anything below this decibel level is considered silent and clipped.
    fileprivate static let silenceDecibelThreshold: Float = -50

    /// The number of samples to collect for the given audio file.
    /// We limit this to restrict the memory space an individual audio
    /// file can consume.
    ///
    /// If rendering waveforms at a higher resolution, this value may
    /// need to be adjusted appropriately.
    ///
    /// Currently, these samples are cached to disk in `TSAttachmentStream`,
    /// so we need to make sure that sample count produces a reasonably file size.
    fileprivate static let sampleCount = 100

    /// The maximum duration asset that we will display waveforms for.
    /// It's too intensive to sample a waveform for really long audio files.
    private static let maximumDuration: TimeInterval = 10 * kMinuteInterval

    private weak var sampleOperation: Operation?

    private func beginSampling(for asset: AVAsset) {
        let operation = AudioWaveformSamplingOperation(asset: asset) { [weak self] samples in
            self?.decibelSamples = samples
            self?.notifyObserversOfSamplingCompletion()
        }
        AudioWaveformSamplingOperation.operationQueue.addOperation(operation)
        sampleOperation = operation
    }

    private func downsample(samples: [Float], toSampleCount sampleCount: Int) -> [Float] {
        // Do nothing if the number of requested samples is less than 1
        guard sampleCount > 0 else { return [] }

        // If the requested sample count is equal to the sample count, just return the samples
        guard samples.count != sampleCount else { return samples }

        // Calculate the number of samples each downsampled value should take into account
        let sampleDistribution = Float(samples.count) / Float(sampleCount)

        // Calculate the number of samples we need to factor in when downsampling. Since there
        // is no such thing as a fractional sample, we need to round this up to the nearest Int.
        // When we calculated the distribution later, it will factor in that some of these samples
        // are weighted differently than others in the resulting output.
        let sampleLength = Int(ceil(sampleDistribution))

        // Calculate the weight of each sample in the downsampled group.
        // For whole number `sampleDistribution` the distribution is always
        // equivalent across all of the samples. If the sampleDistribution
        // is _not_ a whole number, we factor the bookending values in
        // relative to remainder proportion
        let distribution: [Float] = {
            let averageProportion = 1 / sampleDistribution

            var array = [Float](repeating: averageProportion, count: sampleLength)

            if samples.count % sampleCount != 0 {
                // Calculate the proportion that the partial sample should be weighted at
                let remainderProportion = (sampleDistribution.truncatingRemainder(dividingBy: 1)) * averageProportion

                // The partial sample is factored into the "bookends" (first and last element of the distribution)
                // by averaging the average distribution and the remainder distribution together.
                // This provides a lightweight "anti-aliasing" effect.
                let bookEndProportions = (averageProportion + remainderProportion) / 2

                array[0] = bookEndProportions
                array[sampleLength - 1] = bookEndProportions
            }

            return array
        }()

        // If we can ever gurantee that `samples.count` is always a multiple of `sampleCount`, we should
        // switch to using the faster `vDSP_desamp`. For now, we can't use it since it only supports the
        // integer stride lengths. This should be okay, since this should only be operating on already
        // downsampled data (~100 points) rather than the original millions of points.
        let result: [Float] = (0..<sampleCount).map { downsampledIndex in
            let sampleStart = Int(floor(Float(downsampledIndex) * sampleDistribution))
            return samples[sampleStart..<sampleStart + sampleLength].enumerated().reduce(0) { result, value in
                return result + distribution[value.offset] * value.element
            }
        }

        return result
    }

    // MARK: - Observation

    private var observers = [Weak<AudioWaveformSamplingObserver>]()

    private func notifyObserversOfSamplingCompletion() {
        observers.forEach {
            $0.value?.audioWaveformDidFinishSampling(self)
        }
    }

    @objc
    public func addSamplingObserver(_ observer: AudioWaveformSamplingObserver) {
        observers.append(Weak(value: observer))

        // If sampling is already complete, notify the observer immediately.
        guard isSamplingComplete else { return }
        observer.audioWaveformDidFinishSampling(self)
    }
}

private class AudioWaveformSamplingOperation: Operation {
    let asset: AVAsset
    let completionCallback: ([Float]) -> Void

    static let operationQueue: OperationQueue = {
        let operationQueue = OperationQueue()
        operationQueue.name = "org.signal.AudioWaveformSampling"
        return operationQueue
    }()

    init(asset: AVAsset, completionCallback: @escaping ([Float]) -> Void) {
        self.asset = asset
        self.completionCallback = completionCallback
        super.init()
    }

    override func main() {
        var decibelSamples: [Float]?

        defer {
            if let samples = decibelSamples { completionCallback(samples) }
        }

        guard !isCancelled else { return }

        guard let assetReader = try? AVAssetReader(asset: asset) else {
            return owsFailDebug("Unexpectedly failed to initialize asset reader")
        }

        // We just draw the waveform based on the first track.
        guard let audioTrack = assetReader.asset.tracks.first else {
            return owsFailDebug("audio file has no tracks")
        }

        let trackOutput = AVAssetReaderTrackOutput(
            track: audioTrack,
            outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsNonInterleaved: false
            ]
        )
        assetReader.add(trackOutput)

        decibelSamples = readDecibels(from: assetReader)

        // If the operation was cancelled, return nothing as the samples may be incomplete.
        guard !isCancelled else { return decibelSamples = nil }
    }

    private func readDecibels(from assetReader: AVAssetReader) -> [Float] {
        var outputSamples = [Float]()
        var readBuffer = Data()

        let samplesToGroup = max(1, sampleCount(from: assetReader) / AudioWaveform.sampleCount)

        assetReader.startReading()
        while assetReader.status == .reading {
            // Stop reading if the operation is cancelled.
            guard !isCancelled else { break }

            guard let trackOutput = assetReader.outputs.first else {
                owsFailDebug("track output unexpectedly missing")
                break
            }

            // Process any newly read data.
            guard let nextSampleBuffer = trackOutput.copyNextSampleBuffer(),
                let blockBuffer = CMSampleBufferGetDataBuffer(nextSampleBuffer) else {
                    // There is no more data to read, break
                    break
            }

            var readBufferLength = 0
            var readBufferPointer: UnsafeMutablePointer<Int8>?
            CMBlockBufferGetDataPointer(
                blockBuffer,
                atOffset: 0,
                lengthAtOffsetOut: &readBufferLength,
                totalLengthOut: nil,
                dataPointerOut: &readBufferPointer
            )
            readBuffer.append(UnsafeBufferPointer(start: readBufferPointer, count: readBufferLength))
            CMSampleBufferInvalidate(nextSampleBuffer)

            // Try and process any pending samples, we may not have read enough data yet to do this.
            let processedSamples = convertToDecibels(fromAmplitudes: readBuffer, from: assetReader, groupSize: samplesToGroup)
            outputSamples += processedSamples

            // If we successfully processed samples, remove any processed samples
            // from the read buffer.
            if processedSamples.count > 0 {
                readBuffer.removeFirst(processedSamples.count * samplesToGroup * MemoryLayout<Int16>.size)
            }
        }

        return outputSamples
    }

    private func sampleCount(from assetReader: AVAssetReader) -> Int {
        let samplesPerChannel = Int(assetReader.asset.duration.value)

        // We will read in the samples from each channel, interleaved since
        // we only draw one waveform. This gives us an average of the channels
        // if it is, for example, a stereo audio file.
        return samplesPerChannel * channelCount(from: assetReader)
    }

    private func channelCount(from assetReader: AVAssetReader) -> Int {
        guard let output = assetReader.outputs.first as? AVAssetReaderTrackOutput,
            let formatDescriptions = output.track.formatDescriptions as? [CMFormatDescription] else { return 0 }

        var channelCount = 0

        for description in formatDescriptions {
            guard let basicDescription = CMAudioFormatDescriptionGetStreamBasicDescription(description) else { continue }
            channelCount = Int(basicDescription.pointee.mChannelsPerFrame)
        }

        return channelCount
    }

    private func convertToDecibels(fromAmplitudes sampleBuffer: Data, from assetReader: AVAssetReader, groupSize: Int) -> [Float] {
        var downSampledData = [Float]()

        sampleBuffer.withUnsafeBytes { samples in
            let sampleLength = sampleBuffer.count / MemoryLayout<Int16>.size
            var decibelSamples = [Float](repeating: 0.0, count: sampleLength)

            // maximum amplitude storable in Int16 = 0 dB (loudest)
            var zeroDecibelEquivalent: Float = Float(Int16.max)

            var loudestClipValue: Float = 0.0
            var quietestClipValue = AudioWaveform.silenceDecibelThreshold
            let samplesToProcess = vDSP_Length(sampleLength)

            // convert 16bit int amplitudes to float representation
            vDSP_vflt16([Int16](samples.bindMemory(to: Int16.self)), 1, &decibelSamples, 1, samplesToProcess)

            // take the absolute amplitude value
            vDSP_vabs(decibelSamples, 1, &decibelSamples, 1, samplesToProcess)

            // convert to dB
            vDSP_vdbcon(decibelSamples, 1, &zeroDecibelEquivalent, &decibelSamples, 1, samplesToProcess, 1)

            // clip between loudest + quietest
            vDSP_vclip(decibelSamples, 1, &quietestClipValue, &loudestClipValue, &decibelSamples, 1, samplesToProcess)

            let sampleCount = sampleLength / groupSize
            downSampledData = downsample(samples: decibelSamples, toSampleCount: sampleCount)
        }

        return downSampledData
    }

    private func downsample(samples: [Float], toSampleCount sampleCount: Int) -> [Float] {
        // Do nothing if the number of requested samples is less than 1
        guard sampleCount > 0 else { return [] }

        // Calculate the number of samples each resulting sample should span.
        // If samples.count % sampleCount is > 0, that many samples will
        // be omitted from the resulting array. This is okay, because we don't
        // remove any unprocessed samples from the read buffer and will include
        // them in the next group to downsample.
        let strideLength = samples.count / sampleCount

        // This filter indicates that we should evaluate each sample equally when downsampling.
        let filter = [Float](repeating: 1.0 / Float(strideLength), count: strideLength)
        var downSampledData = [Float](repeating: 0.0, count: sampleCount)

        vDSP_desamp(
            samples,
            vDSP_Stride(strideLength),
            filter,
            &downSampledData,
            vDSP_Length(sampleCount),
            vDSP_Length(strideLength)
        )

        return downSampledData
    }
}
