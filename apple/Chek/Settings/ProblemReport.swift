import Foundation
import UIKit

/// The bug form in readchek/chek, the one place problems with any part of
/// Chek are reported, with the fields Settings already knows filled in.
/// Launch week brings first-time reporters, and the version and device
/// are what most reports leave out.
nonisolated enum ProblemReport {
    static let form = URL(string: "https://github.com/readchek/chek/issues/new")!

    /// The form with the app's version, the device and its system filled
    /// in. GitHub takes each field's value by its id in the query, and a
    /// dropdown by the text of one of its options.
    static func url(version: String, device: String, system: String) -> URL {
        var components = URLComponents(url: form, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "template", value: "bug.yml"),
            URLQueryItem(name: "area", value: "iPhone or iPad app"),
            URLQueryItem(name: "version", value: "App \(version)"),
            URLQueryItem(name: "device", value: "\(device) on \(system)"),
        ]
        return components.url!
    }

    /// The device's kind and model identifier, such as "iPhone (iPhone17,1)".
    /// The identifier says which iPhone it is; the kind alone doesn't.
    @MainActor static var currentDevice: String {
        let kind = UIDevice.current.model
        guard let machine = machineIdentifier, !machine.isEmpty else { return kind }
        return "\(kind) (\(machine))"
    }

    /// The system's name and version, such as "iPadOS 26.1".
    @MainActor static var currentSystem: String {
        "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"
    }

    private static var machineIdentifier: String? {
        var info = utsname()
        guard uname(&info) == 0 else { return nil }
        // The field is a fixed C char array, read up to its first NUL.
        return withUnsafeBytes(of: &info.machine) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
    }
}
