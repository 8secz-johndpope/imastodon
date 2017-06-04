import Foundation
import Eureka
import SVProgressHUD
import MastodonKit
import SafariServices
import Ikemen

private let statusCellID = "Status"

class TimelineViewController: UICollectionViewController {
    var statuses: [(Status, NSAttributedString?)] // as creating attributed text is heavy, cache it
    let layout = UICollectionViewFlowLayout() ※ { l in
        l.minimumLineSpacing = 0
        l.minimumInteritemSpacing = 0
    }

    init(statuses: [Status] = []) {
        self.statuses = statuses.map {($0, $0.attributedTextContent)}
        super.init(collectionViewLayout: layout)
    }
    required init?(coder aDecoder: NSCoder) {fatalError()}

    override func viewDidLoad() {
        super.viewDidLoad()
        collectionView?.backgroundColor = .white
        collectionView?.showsVerticalScrollIndicator = false
        collectionView?.register(StatusCollectionViewCell.self, forCellWithReuseIdentifier: statusCellID)
    }

    override func willTransition(to newCollection: UITraitCollection, with coordinator: UIViewControllerTransitionCoordinator) {
        super.willTransition(to: newCollection, with: coordinator)
        layout.invalidateLayout()
        collectionView?.reloadData()
    }

    func append(_ statuses: [Status]) {
        statuses.reversed().forEach {
            self.statuses.insert(($0, $0.attributedTextContent), at: 0)
            self.collectionView?.insertItems(at: [IndexPath(item: 0, section: 0)])
        }

        if self.statuses.count > 100 {
            self.statuses.removeLast(self.statuses.count - 80)
            collectionView?.reloadData()
        }
    }

    func status(_ indexPath: IndexPath) -> (Status, NSAttributedString?) {
        return statuses[indexPath.row]
    }

    private func didTap(status: Status, cell: BaseCell, row: BaseRow) {
        let ac = UIAlertController(actionFor: status,
                                   safari: {[unowned self] in self.show($0, sender: nil)},
                                   boost: {},
                                   favorite: {})
        present(ac, animated: true)
    }
}

extension TimelineViewController {
    override func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 1
    }

    override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return statuses.count
    }

    override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: statusCellID, for: indexPath) as! StatusCollectionViewCell
        let s = status(indexPath)
        cell.setStatus(s.0, attributedText: s.1)
        return cell
    }

    override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let s = status(indexPath).0
        let ac = UIAlertController(actionFor: s,
                                   safari: {[unowned self] in self.show($0, sender: nil)},
                                   boost: {},
                                   favorite: {})
        present(ac, animated: true)
    }
}

private let layoutCell = StatusCollectionViewCell(frame: .zero)

extension TimelineViewController: UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let size = collectionView.bounds.size
        let s = status(indexPath)
        layoutCell.setStatus(s.0, attributedText: s.1)
        let layoutSize = layoutCell.systemLayoutSizeFitting(size, withHorizontalFittingPriority: UILayoutPriorityRequired, verticalFittingPriority: UILayoutPriorityFittingSizeLevel)
        return CGSize(width: collectionView.bounds.width, height: layoutSize.height)
    }
}
