import Foundation

enum APIError: Error, LocalizedError, Equatable, Sendable {
  case configuration
  case unavailable
  case invalidResponse
  case server(Int, String)
  case secureStorage

  var errorDescription: String? {
    switch self {
    case .configuration: "The chapter connection is not configured correctly."
    case .unavailable: "Unable to reach the chapter. Check your connection and try again."
    case .invalidResponse: "The chapter update could not be read. Please try again."
    case .server(_, let message): message
    case .secureStorage:
      "Your device could not save a secure sign-in. Unlock it and ask for a new invitation."
    }
  }
  var requiresSignIn: Bool { if case .server(401, _) = self { true } else { false } }
}

protocol ChapterAPI: Sendable {
  func fetchFeed() async throws -> ChapterFeed
  func activate(code: String) async throws -> String
  func fetchMember(token: String) async throws -> MemberProfile
  func respond(token: String, eventID: String, response: RSVPResponse) async throws
  func signOut(token: String) async throws
}

struct HTTPPayload: Sendable {
  let data: Data
  let status: Int
}

protocol HTTPTransport: Sendable {
  func send(_ request: URLRequest) async throws -> HTTPPayload
}

final class RedirectBlocker: NSObject, URLSessionTaskDelegate {
  func urlSession(
    _ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
    completionHandler: @escaping @Sendable (URLRequest?) -> Void
  ) {
    completionHandler(nil)
  }
}

actor NativeHTTPTransport: HTTPTransport {
  private let session: URLSession
  init() {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.urlCache = nil
    configuration.httpCookieStorage = nil
    configuration.httpShouldSetCookies = false
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    configuration.timeoutIntervalForRequest = 20
    configuration.timeoutIntervalForResource = 30
    session = URLSession(
      configuration: configuration, delegate: RedirectBlocker(), delegateQueue: nil)
  }
  func send(_ request: URLRequest) async throws -> HTTPPayload {
    let (data, response) = try await session.data(for: request)
    guard let response = response as? HTTPURLResponse else { throw APIError.invalidResponse }
    return HTTPPayload(data: data, status: response.statusCode)
  }
}

actor NativeChapterAPI: ChapterAPI {
  let configuration: AppConfiguration
  private let transport: any HTTPTransport
  init(configuration: AppConfiguration, transport: any HTTPTransport = NativeHTTPTransport()) {
    self.configuration = configuration
    self.transport = transport
  }

  func makeRequest(path: String, method: String = "GET", token: String? = nil, body: Data? = nil)
    -> URLRequest
  {
    let url = configuration.baseURL.appending(
      path: "api/v1/mobile/\(configuration.chapterSlug)/\(path)")
    var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
    request.httpMethod = method
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
    if let body {
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.httpBody = body
    }
    return request
  }

  private func request(
    path: String, method: String = "GET", token: String? = nil, body: Data? = nil
  ) async throws -> Data {
    do {
      let payload = try await transport.send(
        makeRequest(path: path, method: method, token: token, body: body))
      try Task.checkCancellation()
      guard (200..<300).contains(payload.status) else {
        struct Failure: Decodable { let detail: String }
        let detail = (try? JSONDecoder().decode(Failure.self, from: payload.data))?.detail
        throw APIError.server(
          payload.status, detail ?? "The chapter could not complete this request. Please try again."
        )
      }
      return payload.data
    } catch is CancellationError { throw CancellationError() } catch let error as APIError {
      throw error
    } catch let error as URLError where error.code == .cancelled { throw CancellationError() } catch
    { throw APIError.unavailable }
  }

  private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
    do { return try APICoding.decoder().decode(type, from: data) } catch {
      throw APIError.invalidResponse
    }
  }

  func fetchFeed() async throws -> ChapterFeed {
    let feed = try decode(ChapterFeed.self, from: await request(path: "feed"))
    guard feed.chapter.slug == configuration.chapterSlug else { throw APIError.invalidResponse }
    return feed
  }

  func activate(code: String) async throws -> String {
    struct Activation: Decodable { let token: String }
    let body = try JSONEncoder().encode(["code": code])
    let result = try decode(
      Activation.self, from: await request(path: "activate", method: "POST", body: body))
    guard result.token.hasPrefix("wss_"), result.token.count >= 40 else {
      throw APIError.invalidResponse
    }
    return result.token
  }

  func fetchMember(token: String) async throws -> MemberProfile {
    let member = try decode(MemberProfile.self, from: await request(path: "me", token: token))
    guard member.status == "active" else {
      throw APIError.server(401, "Your membership needs a chapter check before you sign in.")
    }
    return member
  }

  func respond(token: String, eventID: String, response: RSVPResponse) async throws {
    guard eventID.range(of: "^cms-[0-9]+$", options: .regularExpression) != nil else {
      throw APIError.invalidResponse
    }
    let body = try JSONEncoder().encode(["response": response.rawValue])
    _ = try await request(path: "events/\(eventID)/rsvp", method: "PUT", token: token, body: body)
  }

  func signOut(token: String) async throws {
    _ = try await request(path: "session", method: "DELETE", token: token)
  }
}
