import Foundation

/// Static example-app configuration.
enum DemoConfig {
    /// Tenant SDK key (`pk_live_…`) used to pre-fill the enrollment screen. Leave empty
    /// and type your key in the app, or paste it here for convenience. The key is
    /// provided by Hopcast with your account.
    static let defaultSdkKey = ""

    /// Default user identifier the device is enrolled under.
    static let defaultUserId = "demo-user"

    /// Advanced: connection override for the online mode. Leave `nil` (default) unless
    /// Hopcast support instructs otherwise.
    static let brokerOverride: String? = nil

    /// Where received / demo files live. The file name is the `content_id`.
    static var cacheDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("hopcast-demo/cache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
