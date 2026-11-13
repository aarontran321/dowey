//
//  Updater.swift
//  Dowey
//
//  Finds a newer release on GitHub and installs it in place.
//
//  Check: one request to the GitHub releases API, made when Dowey launches,
//  when its menu opens and when Settings opens — at most once every six hours,
//  and never on a timer. It is the only network request Dowey makes, and the
//  "Check for updates" setting turns it off.
//
//  Install: download the release zip, unpack it next to the running app, and
//  refuse it unless it is Dowey, is the version the release claims, and is
//  signed by the same developer as the running copy — checked against the
//  running app's own designated requirement, so no key or certificate is
//  baked in here. Then the new bundle is swapped into place and Dowey
//  relaunches into it. Because Dowey downloads the archive itself, macOS does
//  not quarantine it, so the update opens without the Gatekeeper prompt a
//  browser download gets.
//

import AppKit
import Security

@MainActor
final class Updater: ObservableObject {

    static let shared = Updater()

    struct Release: Equatable {
        let version: Version
        let archive: URL
        let page: URL
    }

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(Release)
        case installing(Release)
        /// `release` is set when the failure happened installing it, so the
        /// UI can offer the release page as the way forward.
        case failed(message: String, release: Release?)
    }

    @Published private(set) var state: State = .idle

    let currentVersion: Version

    private static let repository = "aarontran321/dowey"
    private static let checkInterval: TimeInterval = 6 * 60 * 60
    private static let lastCheckKey = "lastUpdateCheck"

    private let feed: URL
    private let defaults: UserDefaults

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        currentVersion = version.flatMap(Version.init) ?? Version("0")!

        var feed = URL(string: "https://api.github.com/repos/\(Self.repository)/releases/latest")!
        #if DEBUG
        // Lets a debug build be pointed at a local feed to exercise the whole
        // install path without publishing anything.
        if let override = ProcessInfo.processInfo.environment["DOWEY_UPDATE_FEED"].flatMap(URL.init(string:)) {
            feed = override
        }
        #endif
        self.feed = feed
    }

    private var isBusy: Bool {
        switch state {
        case .checking, .installing: return true
        default: return false
        }
    }

    // MARK: - Checking

    /// The automatic check. Quiet: it does nothing if the user turned checks
    /// off, if one ran in the last six hours, or if anything is in flight, and
    /// a failure leaves the state as it was.
    func checkIfDue() {
        guard Settings.shared.checkForUpdates, !isBusy else { return }
        if let last = defaults.object(forKey: Self.lastCheckKey) as? Date,
           Date().timeIntervalSince(last) < Self.checkInterval {
            return
        }
        Task { await check(reportingFailure: false) }
    }

    /// The Check Now button: always runs, and says so when it fails.
    func checkNow() {
        guard !isBusy else { return }
        Task { await check(reportingFailure: true) }
    }

    private func check(reportingFailure: Bool) async {
        let previous = state
        state = .checking
        do {
            let release = try await fetchLatestRelease()
            defaults.set(Date(), forKey: Self.lastCheckKey)
            state = release.version > currentVersion ? .available(release) : .upToDate
        } catch {
            state = reportingFailure
                ? .failed(message: "Couldn't reach GitHub.", release: nil)
                : previous
        }
    }

    private struct ReleasePayload: Decodable {
        struct Asset: Decodable {
            let name: String
            let browserDownloadUrl: URL
        }
        let tagName: String
        let htmlUrl: URL
        let assets: [Asset]
    }

    private func fetchLatestRelease() async throws -> Release {
        var request = URLRequest(url: feed, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Dowey/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError.unreadableRelease }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let payload = try decoder.decode(ReleasePayload.self, from: data)

        guard let version = Version(payload.tagName),
              let asset = payload.assets.first(where: { $0.name == "Dowey-\(version).zip" })
        else { throw UpdateError.unreadableRelease }

        return Release(version: version, archive: asset.browserDownloadUrl, page: payload.htmlUrl)
    }

    // MARK: - Installing

    func install() {
        guard case .available(let release) = state else { return }
        state = .installing(release)
        Task {
            do {
                let current = Bundle.main.bundleURL
                guard !current.path.contains("/AppTranslocation/") else { throw UpdateError.translocated }

                let workspace = try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                                            appropriateFor: current, create: true)
                defer { try? FileManager.default.removeItem(at: workspace) }

                let candidate = try await download(release, into: workspace)
                try verify(candidate, claims: release.version)
                do {
                    _ = try FileManager.default.replaceItemAt(current, withItemAt: candidate)
                } catch {
                    throw UpdateError.notWritable
                }
                try relaunch(at: current)
            } catch let error as UpdateError {
                state = .failed(message: error.message, release: release)
            } catch {
                state = .failed(message: UpdateError.downloadFailed.message, release: release)
            }
        }
    }

    func openReleasePage(_ release: Release?) {
        let url = release?.page ?? URL(string: "https://github.com/\(Self.repository)/releases/latest")!
        NSWorkspace.shared.open(url)
    }

    /// Downloads and unpacks the archive inside `workspace`, which sits on the
    /// same volume as the running app so the final swap is a rename.
    private func download(_ release: Release, into workspace: URL) async throws -> URL {
        let (temporary, response) = try await URLSession.shared.download(from: release.archive)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError.downloadFailed }

        let archive = workspace.appendingPathComponent("Dowey.zip")
        try FileManager.default.moveItem(at: temporary, to: archive)

        let unpacked = workspace.appendingPathComponent("unpacked", isDirectory: true)
        try await run("/usr/bin/ditto", ["-x", "-k", archive.path, unpacked.path])

        let app = unpacked.appendingPathComponent("Dowey.app", isDirectory: true)
        guard FileManager.default.fileExists(atPath: app.path) else { throw UpdateError.notDowey }
        return app
    }

    /// The new bundle has to be Dowey, has to be the version the release said
    /// it was, and has to satisfy the running app's designated requirement —
    /// the same bundle identifier signed by the same developer. A zip swapped
    /// out on the server fails the last check however it is labelled.
    private func verify(_ app: URL, claims version: Version) throws {
        guard let bundle = Bundle(url: app),
              bundle.bundleIdentifier == Bundle.main.bundleIdentifier
        else { throw UpdateError.notDowey }

        guard let shortVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              Version(shortVersion) == version
        else { throw UpdateError.notDowey }

        var running: SecCode?
        var runningOnDisk: SecStaticCode?
        var requirement: SecRequirement?
        var candidate: SecStaticCode?
        guard SecCodeCopySelf([], &running) == errSecSuccess, let running,
              SecCodeCopyStaticCode(running, [], &runningOnDisk) == errSecSuccess, let runningOnDisk,
              SecCodeCopyDesignatedRequirement(runningOnDisk, [], &requirement) == errSecSuccess, let requirement,
              SecStaticCodeCreateWithPath(app as CFURL, [], &candidate) == errSecSuccess, let candidate
        else { throw UpdateError.badSignature }

        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
        guard SecStaticCodeCheckValidity(candidate, flags, requirement) == errSecSuccess else {
            throw UpdateError.badSignature
        }
    }

    /// Hands off to a shell that waits for this process to exit and then opens
    /// the new bundle, so the two copies never run at once.
    private func relaunch(at app: URL) throws {
        let waiter = Process()
        waiter.executableURL = URL(fileURLWithPath: "/bin/sh")
        waiter.arguments = ["-c",
                            "while /bin/kill -0 \"$1\" 2>/dev/null; do /bin/sleep 0.1; done; /usr/bin/open \"$2\"",
                            "dowey-relaunch",
                            String(ProcessInfo.processInfo.processIdentifier),
                            app.path]
        try waiter.run()
        NSApp.terminate(nil)
    }

    private func run(_ tool: String, _ arguments: [String]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: tool)
            process.arguments = arguments
            process.terminationHandler = { finished in
                if finished.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: UpdateError.downloadFailed)
                }
            }
            do { try process.run() } catch { continuation.resume(throwing: error) }
        }
    }
}

private enum UpdateError: Error {
    case unreadableRelease
    case downloadFailed
    case notDowey
    case badSignature
    case notWritable
    case translocated

    var message: String {
        switch self {
        case .unreadableRelease: return "Couldn't read the latest release."
        case .downloadFailed:    return "The download failed."
        case .notDowey:          return "The download isn't a Dowey build."
        case .badSignature:      return "The download isn't signed by Dowey's developer."
        case .notWritable:       return "Dowey can't replace itself in this folder."
        case .translocated:      return "Move Dowey to Applications first."
        }
    }
}
