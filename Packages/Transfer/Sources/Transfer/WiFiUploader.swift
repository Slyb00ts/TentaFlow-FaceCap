// =============================================================================
// Plik: WiFiUploader.swift
// Opis: Bonjour discovery + multipart upload do urządzenia Rack-Eye w sieci lokalnej.
// =============================================================================

import Foundation
import Network
import Shared

/// Uploader przez sieć lokalną. Znajduje urządzenie Rack-Eye (Bonjour
/// `_rackeye._tcp.local.`), po czym wysyła plik `.face` multipartem.
public final class WiFiUploader: NSObject {

    /// Typ serwisu Bonjour rozgłaszanego przez Tab5.
    public static let bonjourType: String = "_rackeye._tcp."

    /// Endpoint HTTP na urządzeniu docelowym do odbioru pliku `.face`.
    public static let uploadPath: String = "/api/v1/face/upload"

    private let progress: TransferProgress
    private let browser: NWBrowser
    private var selectedEndpoint: NWEndpoint?

    public init(progress: TransferProgress) {
        self.progress = progress
        let params = NWParameters()
        params.includePeerToPeer = true
        self.browser = NWBrowser(
            for: .bonjourWithTXTRecord(type: WiFiUploader.bonjourType, domain: nil),
            using: params
        )
        super.init()
    }

    /// Znajdź urządzenie i wyślij plik. Wartość zwracana: `true` = sukces.
    @MainActor
    public func upload(fileURL: URL, timeout: TimeInterval = 8) async throws {
        progress.setStatus(.preparing)

        let endpoint = try await discoverEndpoint(timeout: timeout)
        self.selectedEndpoint = endpoint
        AppLog.transfer.info("Found endpoint: \(String(describing: endpoint), privacy: .public)")

        // Budujemy URL z endpointa Bonjour.
        let url = try buildURL(from: endpoint)
        try await sendMultipart(to: url, fileURL: fileURL)
    }

    // MARK: — Bonjour

    private func discoverEndpoint(timeout: TimeInterval) async throws -> NWEndpoint {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<NWEndpoint, Error>) in

            var didResume = false
            let lock = NSLock()

            func resumeOnce(_ result: Result<NWEndpoint, Error>) {
                lock.lock()
                let shouldResume = !didResume
                didResume = true
                lock.unlock()
                guard shouldResume else { return }
                switch result {
                case .success(let ep): cont.resume(returning: ep)
                case .failure(let e): cont.resume(throwing: e)
                }
            }

            browser.browseResultsChangedHandler = { [weak self] results, _ in
                guard self != nil else { return }
                if let first = results.first {
                    resumeOnce(.success(first.endpoint))
                }
            }
            browser.stateUpdateHandler = { state in
                switch state {
                case .failed(let error):
                    resumeOnce(.failure(error))
                default:
                    break
                }
            }
            browser.start(queue: .global(qos: .userInitiated))

            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                resumeOnce(.failure(FacecapError.noTransferReceiver))
            }
        }
    }

    private func buildURL(from endpoint: NWEndpoint) throws -> URL {
        // Dla endpointów Bonjour iOS zwraca najczęściej .service(name:type:domain:interface:)
        // — używamy rozwiązania DNS-SD runtime, co oznacza, że musimy „rozwiązać” hosta
        // przez krótkie połączenie NWConnection (niskopoziomowe).
        switch endpoint {
        case .service(let name, _, _, _):
            // Whitelistujemy znaki dozwolone w nazwie hosta mDNS, żeby nikt nie wstrzyknął
            // np. znaków kontrolnych czy slashy do ścieżki URL.
            let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
            guard name.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
                throw FacecapError.invalidArgument("Niebezpieczna nazwa serwisu Bonjour: \(name)")
            }
            guard let url = URL(string: "http://\(name).local\(WiFiUploader.uploadPath)") else {
                throw FacecapError.uploadFailed("Nie udało się zbudować URL z usługi \(name).")
            }
            return url
        case .hostPort(let host, let port):
            let hostString: String
            switch host {
            case .name(let n, _): hostString = n
            case .ipv4(let ip): hostString = "\(ip)"
            case .ipv6(let ip): hostString = "\(ip)"
            @unknown default: hostString = ""
            }
            guard let url = URL(string: "http://\(hostString):\(port.rawValue)\(WiFiUploader.uploadPath)") else {
                throw FacecapError.uploadFailed("Zły hostPort endpoint.")
            }
            return url
        default:
            throw FacecapError.uploadFailed("Nieobsługiwany rodzaj endpointu Bonjour.")
        }
    }

    // MARK: — Upload

    private func sendMultipart(to url: URL, fileURL: URL) async throws {
        progress.setStatus(.transferring)

        let boundary = "FaceCap-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue(fileURL.lastPathComponent, forHTTPHeaderField: "X-File-Name")

        // Budujemy body w pliku tymczasowym — unikamy trzymania wszystkiego w RAM.
        let bodyURL = try buildMultipartBody(fileURL: fileURL, boundary: boundary)
        defer { try? FileManager.default.removeItem(at: bodyURL) }

        let delegate = UploadDelegate(progress: progress)
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: .main)

        let (resp, rawData) = try await session.upload(for: request, fromFile: bodyURL)
        guard let http = resp as? HTTPURLResponse else {
            throw FacecapError.uploadFailed("Brak HTTPURLResponse.")
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: rawData, encoding: .utf8) ?? ""
            throw FacecapError.uploadFailed("HTTP \(http.statusCode): \(body)")
        }
        progress.update(progress: 1.0, detail: "Wysłano (\(http.statusCode)).")
        progress.setStatus(.finished)
    }

    private func buildMultipartBody(fileURL: URL, boundary: String) throws -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("facecap-upload-\(UUID().uuidString).bin")

        FileManager.default.createFile(atPath: tmp.path, contents: nil)
        guard let handle = try? FileHandle(forWritingTo: tmp) else {
            throw FacecapError.ioError("Nie udało się otworzyć temp file.")
        }
        defer { try? handle.close() }

        func writeString(_ s: String) throws {
            guard let d = s.data(using: .utf8) else {
                throw FacecapError.ioError("UTF-8 encoding fail.")
            }
            try handle.write(contentsOf: d)
        }

        try writeString("--\(boundary)\r\n")
        try writeString("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileURL.lastPathComponent)\"\r\n")
        try writeString("Content-Type: application/octet-stream\r\n\r\n")

        // Kopiujemy plik .face strumieniem (64 KB bloki).
        guard let reader = try? FileHandle(forReadingFrom: fileURL) else {
            throw FacecapError.ioError("Nie można otworzyć pliku wejściowego.")
        }
        defer { try? reader.close() }

        while true {
            let chunk = try reader.read(upToCount: 64 * 1024) ?? Data()
            if chunk.isEmpty { break }
            try handle.write(contentsOf: chunk)
        }
        try writeString("\r\n--\(boundary)--\r\n")
        return tmp
    }
}

/// Delegat `URLSession` — aktualizuje `TransferProgress` podczas wysyłania.
private final class UploadDelegate: NSObject, URLSessionTaskDelegate {

    private let progress: TransferProgress

    init(progress: TransferProgress) {
        self.progress = progress
    }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64,
                    totalBytesExpectedToSend: Int64) {
        let frac: Double
        if totalBytesExpectedToSend > 0 {
            frac = Double(totalBytesSent) / Double(totalBytesExpectedToSend)
        } else {
            frac = 0
        }
        Task { @MainActor in
            self.progress.update(progress: frac, detail: "Wysyłam \(totalBytesSent)/\(totalBytesExpectedToSend) B")
        }
    }
}
