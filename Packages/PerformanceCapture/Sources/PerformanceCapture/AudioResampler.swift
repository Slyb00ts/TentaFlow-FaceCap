// =============================================================================
// Plik: AudioResampler.swift
// Opis: Resample audio do 16 kHz mono s16le przez AVAudioConverter (fallback 48k).
// =============================================================================

import Foundation
import AVFoundation
import os

/// Resampler wykorzystujący `AVAudioConverter` do konwersji dowolnego formatu
/// PCM do docelowego 16 kHz mono s16le.
///
/// Hot path: konwersja odbywa się w jednym wywołaniu `convert(_:toBufferOfSize:)`
/// — brak pętli over-budget w callbacku, brak alokacji poza pojedynczym buforem
/// wyjściowym którego rozmiar wynika z `outputFrameCapacity`.
public final class AudioResampler {

    /// Docelowa częstotliwość próbkowania.
    public static let targetSampleRate: Double = 16_000.0

    private let log = Logger(subsystem: "pl.tentaflow.facecap", category: "audio-resampler")

    public init() {}

    /// Resample’uje pojedynczy bufor PCM do 16 kHz mono s16le.
    ///
    /// - Parameter input: Bufor wejściowy z dowolną częstotliwością.
    /// - Returns: `Data` z surowym PCM s16le (little endian) gotowy do WAV/raw.
    /// - Throws: `PerformanceCaptureError.resampleFailed` przy błędach konwertera.
    public func resample(_ input: AVAudioPCMBuffer) throws -> Data {
        let srcFormat = input.format
        if srcFormat.sampleRate == Self.targetSampleRate,
           srcFormat.channelCount == 1,
           srcFormat.commonFormat == .pcmFormatInt16 {
            // Już w poprawnym formacie — ominięcie konwertera.
            return rawData(from: input)
        }

        guard let dstFormat = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                            sampleRate: Self.targetSampleRate,
                                            channels: 1,
                                            interleaved: true) else {
            throw PerformanceCaptureError.resampleFailed("nie da się utworzyć docelowego formatu")
        }

        guard let converter = AVAudioConverter(from: srcFormat, to: dstFormat) else {
            throw PerformanceCaptureError.resampleFailed("AVAudioConverter == nil")
        }

        let ratio = dstFormat.sampleRate / srcFormat.sampleRate
        let outCapacity = AVAudioFrameCount(Double(input.frameLength) * ratio + 1024)
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: dstFormat,
                                                frameCapacity: outCapacity) else {
            throw PerformanceCaptureError.resampleFailed("nie można alokować bufora wyjściowego")
        }

        var consumedOnce = false
        var error: NSError?
        let status = converter.convert(to: outBuffer, error: &error) { _, outStatus in
            if consumedOnce {
                outStatus.pointee = .endOfStream
                return nil
            }
            consumedOnce = true
            outStatus.pointee = .haveData
            return input
        }
        if let error {
            throw PerformanceCaptureError.resampleFailed("AVAudioConverter.convert: \(error.localizedDescription)")
        }
        if status == .error {
            throw PerformanceCaptureError.resampleFailed("AVAudioConverter status == .error")
        }

        return rawData(from: outBuffer)
    }

    /// Resample’uje plik audio (WAV/CAF/AAC) do 16 kHz mono s16le w pamięci.
    public func resampleFile(at url: URL) throws -> Data {
        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: url)
        } catch {
            throw PerformanceCaptureError.resampleFailed("nie można otworzyć pliku: \(error)")
        }

        let frameCount = AVAudioFrameCount(file.length)
        guard let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                          frameCapacity: frameCount) else {
            throw PerformanceCaptureError.resampleFailed("alokacja bufora pliku nie powiodła się")
        }
        do {
            try file.read(into: buf)
        } catch {
            throw PerformanceCaptureError.resampleFailed("odczyt pliku: \(error)")
        }
        return try resample(buf)
    }

    // MARK: - Prywatne

    /// Zwraca surowe bajty PCM z bufora (Int16 → Data). Zakłada format int16 interleaved.
    private func rawData(from buffer: AVAudioPCMBuffer) -> Data {
        let frameLen = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        let byteCount = frameLen * channelCount * MemoryLayout<Int16>.size

        // Preferujemy int16 channel data; jeśli bufor jest float to kwantyzujemy ręcznie.
        if let int16Ptr = buffer.int16ChannelData {
            // Interleaved int16 → kopiuj jednym memcpy.
            return Data(bytes: int16Ptr.pointee, count: byteCount)
        }
        if let floatPtr = buffer.floatChannelData {
            var out = Data(count: byteCount)
            out.withUnsafeMutableBytes { raw in
                guard let dst = raw.baseAddress?.assumingMemoryBound(to: Int16.self) else { return }
                let src = floatPtr.pointee
                for i in 0..<(frameLen * channelCount) {
                    let clamped = max(-1.0, min(1.0, src[i]))
                    dst[i] = Int16(clamped * Float(Int16.max))
                }
            }
            return out
        }
        log.error("Nieobsługiwany format bufora PCM")
        return Data()
    }
}
