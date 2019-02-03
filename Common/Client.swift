import BrightFutures
import Foundation
import APIKit
#if os(OSX)
import SwiftRichString
#endif
import API

enum AppError: LocalizedError {
    case apikit(SessionTaskError)
    case eventstream(Error?)

    var errorDescription: String? {
        switch self {
        case let .apikit(.connectionError(e)): return "connectionError(\(e))"
        case let .apikit(.requestError(e)): return "requestError(\(e))"
        case let .apikit(.responseError(e)): return "responseError(\(e))"
        case let .eventstream(e): return "AppError.eventstream(\(e?.localizedDescription ?? ""))"
        }
    }
}

struct InstanceAccout: Codable {
    var instance: API.Instance
    var account: Account
    var accessToken: String
}
extension Instance {
    var baseURL: URL? {return URL(string: "https://" + uri)}
}

extension String {
    var emptyNullified: String? {
        return isEmpty ? nil : self
    }
}

extension Account {
    func avatarURL(baseURL: URL?) -> URL? {
        return URL(string: avatar, relativeTo: baseURL) ?? URL(string: avatar_static, relativeTo: baseURL)
    }

    var displayNameOrUserName: String {
        return display_name.emptyNullified ?? username
    }
}

extension Status {
    var mainContentStatus: Status {
        return reblog?.value ?? self
    }

    var textContent: String {
        return attributedTextContent?.string ?? content
    }

    var attributedTextContent: NSAttributedString? {
        return NSAttributedString(html: content)
    }
}

extension NSAttributedString {
    convenience init?(html: String) {
        // TODO: unify logic for platforms
        #if !os(OSX)
            guard let data = ("<style>body {font:-apple-system-body;line-height:100%;} p {margin:0;padding:0;display:inline;}</style>" + html).data(using: .utf8) else { return nil }
            try? self.init(data: data,
                           options: [
                            .documentType: NSAttributedString.DocumentType.html,
                            .characterEncoding: String.Encoding.utf8.rawValue],
                           documentAttributes: nil)
        #else
        let text = html
            .replacingOccurrences(of: "<br />", with: "\n")
            .set(style: StyleGroup(
                base: Style(),
                ["a": Style(),
                 "span": Style(),
                 "p": Style()]))
            .string
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
        self.init(attributedString: text.set(style: Style {
            $0.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        }))
        #endif
    }
}

struct Client {
    let baseURL: URL
    var accessToken: String? {
        didSet {authorizedSession = Client.authorizedSession(accessToken: accessToken)}
    }
    let account: Account?
    private var authorizedSession: Session?
    private static func authorizedSession(accessToken: String?) -> Session? {
        return accessToken.map { accessToken in
            let configuration = URLSessionConfiguration.default
            configuration.httpAdditionalHeaders = ["Authorization": "Bearer \(accessToken)"]
            return Session(adapter: URLSessionAdapter(configuration: configuration))
        }
    }

    fileprivate var caches = Caches()
    fileprivate class Caches {
        var isPinsSupported: Bool?
    }

    func run<Request: APIBlueprintRequest>(_ request: Request) -> Future<Request.Response, AppError> {
        return Future { complete in
            (authorizedSession ?? Session.shared).send(request, handler: complete)?.resume()
            }.mapError {.apikit($0)}
    }

    init(baseURL: URL, accessToken: String? = nil, account: Account?) {
        self.baseURL = baseURL
        self.accessToken = accessToken
        self.authorizedSession = Client.authorizedSession(accessToken: accessToken)
        self.account = account
    }

    init?(_ instanceAccount: InstanceAccout) {
        guard let baseURL = instanceAccount.instance.baseURL else { return nil }
        self.init(baseURL: baseURL, accessToken: instanceAccount.accessToken, account: instanceAccount.account)
    }
}

extension Client {
    func registerApp(clientName: String? = nil) -> Future<ClientApplication, AppError> {
        return run(RegisterApp(baseURL: baseURL, pathVars: .init(
            client_name: clientName ?? "imastodon-banjun",
            redirect_uris: "urn:ietf:wg:oauth:2.0:oob",
            scopes: "read write follow",
            website: "https://imastodon.banjun.jp/"))).map { r in
                switch r {
                case let .http200_(app):
                    print("id: \(app.id)")
                    print("redirect uri: \(app.redirect_uri)")
                    print("client id: \(app.client_id)")
                    print("client secret: \(app.client_secret)")
                    return app
                }
        }
    }

    func login(app: ClientApplication, email: String, password: String) -> Future<LoginSettings, AppError> {
        return run(LoginSilentFormURLEncoded(baseURL: baseURL, param: .init(
            client_id: app.client_id,
            client_secret: app.client_secret,
            scope: "read write follow",
            grant_type: "password",
            username: email,
            password: password))).map { r in
                switch r {
                case let .http200_(settings): return settings
                }
        }
    }

    func currentUser() -> Future<Account, AppError> {
        return run(GetCurrentUser(baseURL: baseURL)).map { r in
            switch r {
            case let .http200_(account): return account
            }
        }
    }

    func currentInstance() -> Future<Instance, AppError> {
        return run(GetInstance(baseURL: baseURL)).map { r in
            switch r {
            case let .http200_(instance): return instance
            }
        }
    }
}

extension Client {
    func home(since: ID? = nil) -> Future<[Status], AppError> {
        return run(GetHomeTimeline(baseURL: baseURL, pathVars: .init(max_id: nil, since_id: since?.value, limit: nil))).map { r in
            switch r {
            case let .http200_(statuses): return statuses
            }
        }
    }

    func local(since: ID? = nil) -> Future<[Status], AppError> {
        return run(GetPublicTimeline(baseURL: baseURL, pathVars: .init(local: "true", max_id: nil, since_id: since?.value, limit: nil))).map { r in
            switch r {
            case let .http200_(statuses): return statuses
            }
        }
    }
    
    func boost(_ status: Status) -> Future<Void, AppError> {
        return run(Boost(baseURL: baseURL, pathVars: .init(id: status.id.value))).asVoid()
    }

    func favorite(_ status: Status) -> Future<Status, AppError> {
        return run(Favorite(baseURL: baseURL, pathVars: .init(id: status.id.value)))
            .map {switch $0 {case .http200_(let s): return s}}
    }

    func unfavorite(_ status: Status) -> Future<Status, AppError> {
        return run(UnFavorite(baseURL: baseURL, pathVars: .init(id: status.id.value)))
            .map {switch $0 {case .http200_(let s): return s}}
    }

    // caution: mastodon before 1.6.0 does not support pins and response with normal toots regardless of pineed=true query.
    private func accountStatuses(accountID: ID, pinned: Bool = false, limit: Int) -> Future<[Status], AppError> {
        return run(GetAccountsStatuses(baseURL: baseURL, pathVars: .init(id: accountID.value, only_media: nil, pinned: pinned ? "true" : nil, exclude_replies: nil, max_id: nil, since_id: nil, limit: String(limit))))
            .map { r in
                switch r {
                case let .http200_(toots): return toots
                }
        }
    }

    // estimate the instance supports pinned toots
    private func isPinsSupported() -> Future<Bool, AppError> {
        if let cached = caches.isPinsSupported { return Future(value: cached) }
        guard let id = account?.id else { return Future(value: false) }
        return accountStatuses(accountID: id, pinned: false, limit: 1).map {$0.first?.pinned != nil}
            .onSuccess {self.caches.isPinsSupported = $0}
    }

    func accountStatuses(accountID: ID, includesPinnedStatuses: Bool = false, limit: Int = 40) -> Future<[Status], AppError> {
        let maxPins = 5
        return (includesPinnedStatuses ? isPinsSupported() : Future(value: false))
            .flatMap { $0 ?
                self.accountStatuses(accountID: accountID, pinned: true, limit: maxPins)
                : Future(value: [])}
            .map {$0.map {s in var s = s; s.pinned = true; return s}} // mark as pinned, the response does not contain pinned when the accountID is not the current API user
            .flatMap { pins in
                self.accountStatuses(accountID: accountID, pinned: false, limit: limit).map {pins + $0}}
    }
}

extension Client {
    func post(message: String, visibility: Visibility = .public) -> Future<Status, AppError> {
        return run(PostStatus(baseURL: baseURL, pathVars: .init(
            status: message,
            in_reply_to_id: nil,
            media_ids: nil,
            sensitive: nil,
            spoiler_text: nil,
            visibility: visibility.rawValue))).map { r in
                switch r {
                case let .http200_(status): return status
                }
        }
    }
}

extension Visibility {
    var displayName: String {return displayPrefix + " " + rawValue}
    var displayPrefix: String {
        switch self {
        case .public: return "🌐"
        case .unlisted: return "🏠"
        case .private: return "🔒"
        case .direct: return "✉️"
        }
    }
}
