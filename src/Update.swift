import Cocoa

// DELIBERATELY TEMPORARY.
//
// This tells you that a newer version exists; it never installs one. Sparkle
// is expected to replace it, and when that lands this whole file goes, with
// the menu item and the version tests. Do not build on it.
//
// See docs/adr/0001 for why the app is free to take a self-replacing updater
// at all: the Rule is narrow enough that a hostile update gains nothing.

struct Release {
    let version: String
    let pageURL: URL
}

enum Update {
    static let apiURL = URL(string: "https://api.github.com/repos/jdanino/sleepless/releases/latest")!

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// Compares two dotted versions. 1.10 is newer than 1.9, and 1.2 is newer
    /// than 1.2 is not.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let b = current.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    /// Asks GitHub for the newest release. A `nil` release means this build is
    /// the newest one. The callback comes on the main thread.
    static func check(completion: @escaping (Result<Release?, Failure>) -> Void) {
        var request = URLRequest(url: apiURL, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Sleepless/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { data, response, error in
            let finish: (Result<Release?, Failure>) -> Void = { result in
                DispatchQueue.main.async { completion(result) }
            }
            if let error {
                return finish(.failure(Failure(error.localizedDescription)))
            }
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard code == 200, let data else {
                return finish(.failure(Failure("GitHub answered with status \(code).")))
            }
            guard
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let tag = json["tag_name"] as? String,
                let page = json["html_url"] as? String,
                let url = URL(string: page)
            else {
                return finish(.failure(Failure("The answer from GitHub could not be read.")))
            }
            let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            finish(.success(isNewer(version, than: currentVersion)
                            ? Release(version: version, pageURL: url) : nil))
        }.resume()
    }
}
