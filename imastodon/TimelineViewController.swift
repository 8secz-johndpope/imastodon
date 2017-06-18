import Foundation
import SVProgressHUD
import SafariServices
import Ikemen

enum TimelineEvent {
    case home(Status, String?) // as creating attributed text is heavy, cache it
    case local(Status, String?) // as creating attributed text is heavy, cache it
    case notification(Notification, String?) // as creating attributed text is buggy, cache it

    var cached: TimelineEvent {
        switch self {
        case let .home(s, nil): return .home(s, s.mainContentStatus.textContent)
        case let .local(s, nil): return .local(s, s.mainContentStatus.textContent)
        case let .notification(n, nil) where n.status != nil: return .notification(n, n.status?.textContent)
        default: return self
        }
    }

    static let homeCellID = "Home"
    static let localCellID = "Local"
    static let notificationCellID = "Notification"

    var cellID: String {
        switch self {
        case .home: return TimelineEvent.homeCellID
        case .local: return TimelineEvent.localCellID
        case .notification: return TimelineEvent.notificationCellID
        }
    }

    var status: Status? {
        switch self {
        case let .home(s, _): return s
        case let .local(s, _): return s
        case .notification: return nil
        }
    }

    var mainContentStatus: Status? {return status?.mainContentStatus}
}

class TimelineViewController: UICollectionViewController {
    var baseURL: URL? // base url for images such as /avatars/original/missing.png
    var timelineEvents: [TimelineEvent]
    let layout = UICollectionViewFlowLayout() ※ { l in
        l.minimumLineSpacing = 0
        l.minimumInteritemSpacing = 0
    }

    init(timelineEvents: [TimelineEvent] = [], baseURL: URL? = nil) {
        self.baseURL = baseURL
        self.timelineEvents = timelineEvents
        super.init(collectionViewLayout: layout)
    }
    required init?(coder aDecoder: NSCoder) {fatalError()}

    override func viewDidLoad() {
        super.viewDidLoad()
        collectionView?.backgroundColor = .white
        collectionView?.showsVerticalScrollIndicator = false
        collectionView?.register(StatusCollectionViewCell.self, forCellWithReuseIdentifier: TimelineEvent.homeCellID)
        collectionView?.register(StatusCollectionViewCell.self, forCellWithReuseIdentifier: TimelineEvent.localCellID)
        collectionView?.register(NotificationCell.self, forCellWithReuseIdentifier: TimelineEvent.notificationCellID)
    }

    override func willTransition(to newCollection: UITraitCollection, with coordinator: UIViewControllerTransitionCoordinator) {
        super.willTransition(to: newCollection, with: coordinator)
        layout.invalidateLayout()
        collectionView?.reloadData()
    }

    func append(_ events: [TimelineEvent]) {
            events.reversed().forEach { e in
                autoreleasepool {
                    guard !(self.timelineEvents.enumerated().contains { old in
                        guard e.status != nil else { return false }
                        guard old.element.status == e.status else { return false }
                        switch (old.element, e) {
                        case (.home, .local):
                            // upgrade from home to local. (more public)
                            self.timelineEvents[old.offset] = e.cached
                            self.collectionView?.reloadItems(at: [IndexPath(item: old.offset, section: 0)])
                        default: break
                        }
                        return true
                    }) else { return }
                    self.timelineEvents.insert(e.cached, at: 0)
                    self.collectionView?.insertItems(at: [IndexPath(item: 0, section: 0)])
                }
            }

        if self.timelineEvents.count > 100 {
            self.timelineEvents.removeLast(self.timelineEvents.count - 80)
            collectionView?.reloadData()
        }
    }

    func timelineEvent(_ indexPath: IndexPath) -> TimelineEvent {
        return timelineEvents[indexPath.row]
    }
}

protocol ClientContainer {
    var client: Client { get }
}

extension TimelineViewController {
    override func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 1
    }

    override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return timelineEvents.count
    }

    override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let e = timelineEvent(indexPath)
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: e.cellID, for: indexPath)
        switch e {
        case let .home(s, a):
            (cell as? StatusCollectionViewCell)?.setStatus(s, text: a, baseURL: baseURL) { [weak self] a in self?.showAttachment(a) }
        case let .local(s, a):
            (cell as? StatusCollectionViewCell)?.setStatus(s, text: a, baseURL: baseURL) { [weak self] a in self?.showAttachment(a) }
        case let .notification(n, s):
            (cell as? NotificationCell)?.setNotification(n, text: s, baseURL: baseURL)
        }
        return cell
    }

    override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let s = timelineEvent(indexPath).status else { return }
        let ac = UIAlertController(actionFor: s,
                                   safari: {[unowned self] in self.present($0, animated: true)},
                                   boost: {[unowned self] in self.boost(s)},
                                   favorite: {[unowned self] in self.favorite(s)})
        ac.popoverPresentationController?.sourceView = collectionView
        ac.popoverPresentationController?.permittedArrowDirections = .any
        if let cell = collectionView.cellForItem(at: indexPath) as? StatusCollectionViewCell {
            ac.popoverPresentationController?.sourceRect = collectionView.convert(cell.iconView.bounds, from: cell.iconView)
        }
        present(ac, animated: true)
    }
    
    func boost(_ s: Status) {
        guard let client = (self as? ClientContainer)?.client else { return }
        SVProgressHUD.show()
        client.boost(s)
            .onComplete {_ in SVProgressHUD.dismiss()}
    }
    
    func favorite(_ s: Status) {
        guard let client = (self as? ClientContainer)?.client else { return }
        SVProgressHUD.show()
        client.favorite(s)
            .onComplete {_ in SVProgressHUD.dismiss()}
    }

    func showAttachment(_ a: Attachment) {
        guard let url = URL(string: a.url) else { return }
        let vc = SFSafariViewController(url: url)
        present(vc, animated: true)
    }
}

private let layoutCell = StatusCollectionViewCell(frame: .zero)
private let notificationLayoutCell = NotificationCell(frame: .zero)

extension TimelineViewController: UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let size = collectionView.bounds.size

        func statusSize(_ s: Status, _ a: String?, constraint: CGSize) -> CGSize {
            layoutCell.setStatus(s, text: a, baseURL: nil)
            if let a = a, a.characters.count < 16 && constraint.width < size.width {
                layoutCell.bodyLabel.preferredMaxLayoutWidth = size.width / 2 - 42
                let layoutSize = layoutCell.systemLayoutSizeFitting(constraint, withHorizontalFittingPriority: UILayoutPriorityFittingSizeLevel, verticalFittingPriority: UILayoutPriorityFittingSizeLevel)
                return CGSize(width: layoutSize.width, height: layoutSize.height)
            } else {
                layoutCell.bodyLabel.preferredMaxLayoutWidth = size.width - 42
                let layoutSize = layoutCell.systemLayoutSizeFitting(constraint, withHorizontalFittingPriority: UILayoutPriorityRequired, verticalFittingPriority: UILayoutPriorityFittingSizeLevel)
                return CGSize(width: size.width, height: layoutSize.height)
            }
        }

        let e = timelineEvent(indexPath)
        switch e {
        case let .home(s, a): return statusSize(s, a, constraint: size)
        case let .local(s, a): return statusSize(s, a, constraint: UILayoutFittingCompressedSize)
        case let .notification(n, s):
            notificationLayoutCell.setNotification(n, text: s, baseURL: nil)
            let layoutSize = notificationLayoutCell.systemLayoutSizeFitting(size, withHorizontalFittingPriority: UILayoutPriorityRequired, verticalFittingPriority: UILayoutPriorityFittingSizeLevel)
            return CGSize(width: collectionView.bounds.width, height: layoutSize.height)
        }
    }
}
