import Foundation
import IKEventSource
import ReactiveSwift

struct Stream {
    let source: EventSource
    let updateSignal: Signal<Event, AppError>
    private let updateObserver: Observer<Event, AppError>
    let notificationSignal: Signal<Notification, AppError>
    private let notificationObserver: Observer<Notification, AppError>
    
    enum Event {
        case open
        case update(Status)
    }

    init(endpoint: URL, token: String) {
        (updateSignal, updateObserver) = Signal<Event, AppError>.pipe()
        (notificationSignal, notificationObserver) = Signal<Notification, AppError>.pipe()
        source = EventSource(url: endpoint.absoluteString, headers: ["Authorization": "Bearer \(token)"])
        source.onOpen { [weak source, weak updateObserver] in
            NSLog("%@", "EventSource opened: \(String(describing: source))")
            updateObserver?.send(value: .open)
        }
        source.onError { [weak source, weak updateObserver, weak notificationObserver] e in
            NSLog("%@", "EventSource error: \(String(describing: e))")
            source?.invalidate()
            updateObserver?.send(error: .eventstream(e))
            notificationObserver?.send(error: .eventstream(e))
        }
        source.addEventListener("update") { [weak updateObserver] id, event, data in
            do {
                let j = try JSONSerialization.jsonObject(with: data?.data(using: .utf8) ?? Data())
                let status = try Status.decodeValue(j)
                updateObserver?.send(value: .update(status))
            } catch {
                NSLog("%@", "EventSource event update, failed to parse with error \(error): \(String(describing: id)), \(String(describing: event)), \(String(describing: data))")
                updateObserver?.send(error: .eventstream(error))
            }
        }
        source.addEventListener("notification") { [weak notificationObserver] id, event, data in
            do {
                let j = try JSONSerialization.jsonObject(with: data?.data(using: .utf8) ?? Data())
                let notification = try Notification.decodeValue(j)
                notificationObserver?.send(value: notification)
            } catch {
                NSLog("%@", "EventSource event update, failed to parse with error \(error): \(String(describing: id)), \(String(describing: event)), \(String(describing: data))")
                notificationObserver?.send(error: .eventstream(error))
            }
        }
    }

    func close() {
        source.close()
        updateObserver.sendInterrupted()
        notificationObserver.sendInterrupted()
    }
}

extension Stream {
    private init(mastodonForHost host: String, path: String, token: String) {
        let knownSeparatedHosts = [
            "mstdn.jp": "streaming."]
        let streamHost = knownSeparatedHosts[host].map {$0 + host} ?? host
        self.init(endpoint: URL(string: "https://" + streamHost + path)!, token: token)
    }

    init(userTimelineForHost host: String, token: String) {
        self.init(mastodonForHost: host, path: "/api/v1/streaming/user", token: token)
    }

    init(localTimelineForHost host: String, token: String) {
        self.init(mastodonForHost: host, path: "/api/v1/streaming/public/local", token: token)
    }
}

extension AppError {
    var errorStatus: Status {
        let errorAccount = Account(id: 0, username: "", acct: "", displayName: "imastodon.AppError", note: "", url: "", avatar: "", avatarStatic: "", header: "", headerStatic: "", locked: false, createdAt: Date(), followersCount: 0, followingCount: 0, statusesCount: 0)
        return Status(id: 0, uri: "", url: URL(string: "https://localhost/")!, account: errorAccount, inReplyToID: nil, inReplyToAccountID: nil, content: localizedDescription, createdAt: Date(), reblogsCount: 0, favouritesCount: 0, reblogged: nil, favourited: nil, sensitive: nil, spoilerText: "", visibility: .public, mediaAttachments: [], mentions: [], tags: [], application: nil, reblogWrapper: [])
    }
}