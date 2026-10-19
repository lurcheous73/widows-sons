import CryptoKit
import Foundation
import KeychainAccess

protocol SessionStorage: Sendable {
  func read() async throws -> String?
  func write(_ token: String) async throws
  func remove() async throws
}

actor KeychainSessionStorage: SessionStorage {
  private let keychain: Keychain
  private let key: String

  init(namespace: String) {
    keychain = Keychain(service: "uk.thegrange.widowsSons.native")
      // Siri/CarPlay can authenticate while the paired phone is locked, after
      // its first unlock since reboot. The secret remains device-only.
      .accessibility(.afterFirstUnlockThisDeviceOnly)
      .synchronizable(false)
    key = namespace + ".session.v1"
  }
  func read() throws -> String? { try keychain.get(key) }
  func write(_ token: String) throws { try keychain.set(token, key: key) }
  func remove() throws { try keychain.remove(key) }
}

protocol FeedStorage: Sendable {
  func read() async throws -> ChapterFeed?
  func write(_ feed: ChapterFeed) async throws
}

actor NativeFeedCache: FeedStorage {
  private let file: URL
  init(namespace: String, directory: URL? = nil) {
    let root =
      directory
      ?? URL.applicationSupportDirectory.appending(path: "WidowsSons", directoryHint: .isDirectory)
    let hash = SHA256.hash(data: Data(namespace.utf8)).map { String(format: "%02x", $0) }.joined()
    file = root.appending(path: hash + ".public-feed.json")
  }
  func read() throws -> ChapterFeed? {
    guard FileManager.default.fileExists(atPath: file.path) else { return nil }
    return try APICoding.decoder().decode(ChapterFeed.self, from: Data(contentsOf: file))
  }
  func write(_ feed: ChapterFeed) throws {
    try FileManager.default.createDirectory(
      at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    let data = try APICoding.encoder().encode(feed)
    try data.write(to: file, options: [.atomic, .completeFileProtection])
  }
}
