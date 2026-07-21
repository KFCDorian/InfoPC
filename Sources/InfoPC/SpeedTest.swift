import Foundation

/// Speed test de la connexion (débit maximal), via les endpoints publics de
/// Cloudflare — la même infrastructure que speed.cloudflare.com. Mesure le
/// temps de transfert d'un volume connu et en déduit le débit en Mbps.
enum SpeedTest {
    struct Result {
        let downloadMbps: Double
        let uploadMbps: Double?
    }

    private static let downloadBytes = 25_000_000   // 25 Mo
    private static let uploadBytes = 10_000_000      // 10 Mo

    static func run() async -> Result? {
        guard let down = await measureDownload() else { return nil }
        let up = await measureUpload()
        return Result(downloadMbps: down, uploadMbps: up)
    }

    private static func measureDownload() async -> Double? {
        guard let url = URL(string: "https://speed.cloudflare.com/__down?bytes=\(downloadBytes)") else { return nil }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 30

        let start = Date()
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        let elapsed = Date().timeIntervalSince(start)
        guard elapsed > 0 else { return nil }
        return Double(data.count) * 8 / 1_000_000 / elapsed
    }

    private static func measureUpload() async -> Double? {
        guard let url = URL(string: "https://speed.cloudflare.com/__up") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        let payload = Data(count: uploadBytes)

        let start = Date()
        guard let (_, response) = try? await URLSession.shared.upload(for: request, from: payload),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        let elapsed = Date().timeIntervalSince(start)
        guard elapsed > 0 else { return nil }
        return Double(payload.count) * 8 / 1_000_000 / elapsed
    }
}
