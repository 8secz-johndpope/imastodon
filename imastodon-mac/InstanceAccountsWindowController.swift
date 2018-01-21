import Cocoa
import NorthLayout
import Ikemen

final class InstanceAccountsWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private var accounts: [InstanceAccout] {
        get {return StoreFile.shared.store.instanceAccounts}
        set {StoreFile.shared.store.instanceAccounts = accounts}
    }
    private lazy var accountsView: NSTableView = .init() ※ { tv in
        tv.addTableColumn(accountsColumn)
        tv.dataSource = self
        tv.delegate = self
        tv.target = self
        tv.doubleAction = #selector(tableViewDidDoubleClick)
    }
    private lazy var accountsColumn: NSTableColumn = .init(identifier: .init("Account")) ※ { c in
        c.title = "\(StoreFile.shared.store.instanceAccounts.count) Accounts"
    }
    private lazy var addButton: NSButton = .init(title: "Add Mastodon Account...", target: self, action: #selector(addAccount))

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 256, height: 256),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered,
                              defer: false)
        super.init(window: window)
        window.title = "Accounts"
        window.center()

        let view = window.contentView!
        let scrollView = NSScrollView()
        scrollView.documentView = accountsView

        let autolayout = view.northLayoutFormat([:], ["sv": scrollView, "add": addButton])
        autolayout("H:|[sv]|")
        autolayout("H:|-[add]-(>=8)-|")
        autolayout("V:|[sv]-[add]-|")
    }

    required init?(coder: NSCoder) {fatalError()}

    func numberOfRows(in tableView: NSTableView) -> Int {
        return accounts.count
    }

    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        let a = accounts[row]
        return "\(a.account.display_name) (@\(a.account.username)) at \(a.instance.title)"
    }

    @objc private func tableViewDidDoubleClick(_ sender: Any?) {
        appDelegate.appendWindowControllerAndShowWindow(LocalTLWindowController(instanceAccount: accounts[accountsView.clickedRow]))
    }

    @objc private func addAccount() {
        let wc = NewAccountWindowController()
        window?.beginSheet(wc.window!) { r in
            _ = wc // capture & release
            self.accountsView.reloadData()
        }
    }
}

