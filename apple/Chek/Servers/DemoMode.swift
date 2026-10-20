import Foundation

/// A look at Chek with sample books and comics of every kind, read from
/// the public demo server, for someone trying the app for the first time
/// and for App Store review.
///
/// The demo is a server account like any other, with one difference: it
/// doesn't survive a relaunch. It's known by a fixed id, so the store can
/// drop it at launch, keep its reading places on this device alone and
/// show a banner while it's connected.
nonisolated enum DemoMode {
    static let accountID = UUID(uuidString: "D3A0C4E1-5E0B-4C6F-9B7E-0C5A1F2D9E01")!
    static let baseURL = URL(string: "https://demo.chek.page")!
    static let name = String(localized: "Chek Demo")
    /// A shared read-only account on the demo server. Its password is
    /// public: the server holds only sample publications.
    static let user = "demo"
    static let password = "demochekreader"
}
