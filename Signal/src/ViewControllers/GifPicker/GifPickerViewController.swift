//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit
import Reachability
import SignalMessaging
import PromiseKit

@objc
public class GifPickerNavigationViewController: OWSNavigationController {

    @objc
    public weak var approvalDelegate: AttachmentApprovalViewControllerDelegate?

    lazy var gifPickerViewController: GifPickerViewController = {
        let gifPickerViewController = GifPickerViewController()
        gifPickerViewController.delegate = self
        return gifPickerViewController
    }()

    @objc
    init() {
        super.init(owsNavbar: ())
        pushViewController(gifPickerViewController, animated: false)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

extension GifPickerNavigationViewController: GifPickerViewControllerDelegate {
    func gifPickerDidSelect(attachment: SignalAttachment) {
        let attachmentApprovalItem = AttachmentApprovalItem(attachment: attachment, canSave: false)
        let attachmentApproval = AttachmentApprovalViewController(options: [],
                                                                  sendButtonImageName: "send-solid-24",
                                                                  attachmentApprovalItems: [attachmentApprovalItem])
        attachmentApproval.approvalDelegate = self
        pushViewController(attachmentApproval, animated: true) {
            // Remove any selected state in case the user returns "back" to the gif picker.
            self.gifPickerViewController.clearSelectedState()
        }
    }

    func gifPickerDidCancel() {
        dismiss(animated: true)
    }
}

extension GifPickerNavigationViewController: AttachmentApprovalViewControllerDelegate {
    public func attachmentApprovalDidAppear(_ attachmentApproval: AttachmentApprovalViewController) {
        approvalDelegate?.attachmentApprovalDidAppear(attachmentApproval)
    }

    public func attachmentApproval(_ attachmentApproval: AttachmentApprovalViewController,
                                   didApproveAttachments attachments: [SignalAttachment],
                                   messageText: String?) {
        approvalDelegate?.attachmentApproval(attachmentApproval, didApproveAttachments: attachments, messageText: messageText)
    }

    public func attachmentApprovalDidCancel(_ attachmentApproval: AttachmentApprovalViewController) {
        approvalDelegate?.attachmentApprovalDidCancel(attachmentApproval)
    }

    public func attachmentApproval(_ attachmentApproval: AttachmentApprovalViewController,
                                   didChangeMessageText newMessageText: String?) {
        approvalDelegate?.attachmentApproval(attachmentApproval, didChangeMessageText: newMessageText)
    }

    public func attachmentApprovalBackButtonTitle() -> String {
        return CommonStrings.backButton
    }

    public var attachmentApprovalTextInputContextIdentifier: String? {
        return approvalDelegate?.attachmentApprovalTextInputContextIdentifier
    }
}

protocol GifPickerViewControllerDelegate: class {
    func gifPickerDidSelect(attachment: SignalAttachment)
    func gifPickerDidCancel()
}

class GifPickerViewController: OWSViewController, UISearchBarDelegate, UICollectionViewDataSource, UICollectionViewDelegate, GifPickerLayoutDelegate {

    // MARK: Properties

    enum ViewMode {
        case idle, searching, results, noResults, error
    }

    private var viewMode = ViewMode.idle {
        didSet {
            Logger.info("viewMode: \(viewMode)")

            updateContents()
        }
    }

    var lastQuery: String?

    public weak var delegate: GifPickerViewControllerDelegate?

    let searchBar: UISearchBar
    let layout: GifPickerLayout
    let collectionView: UICollectionView
    var noResultsView: UILabel?
    var searchErrorView: UILabel?
    var activityIndicator: UIActivityIndicatorView?
    var hasSelectedCell: Bool = false
    var imageInfos = [GiphyImageInfo]()

    var reachability: Reachability?

    private let kCellReuseIdentifier = "kCellReuseIdentifier"

    var progressiveSearchTimer: Timer?

    // MARK: Initializers

    @available(*, unavailable, message:"use other constructor instead.")
    required init?(coder aDecoder: NSCoder) {
        notImplemented()
    }

    @objc
    required init() {
        self.searchBar = OWSSearchBar()
        self.layout = GifPickerLayout()
        self.collectionView = UICollectionView(frame: CGRect.zero, collectionViewLayout: self.layout)

        super.init(nibName: nil, bundle: nil)

        self.layout.delegate = self
    }

    deinit {
        NotificationCenter.default.removeObserver(self)

        progressiveSearchTimer?.invalidate()
    }

    // MARK: - Dependencies

    var giphyAPI: GiphyAPI {
        return GiphyAPI.sharedInstance
    }

    // MARK: -
    @objc func didBecomeActive() {
        AssertIsOnMainThread()

        Logger.info("")

        // Prod cells to try to load when app becomes active.
        ensureCellState()
    }

    @objc func reachabilityChanged() {
        AssertIsOnMainThread()

        Logger.info("")

        // Prod cells to try to load when connectivity changes.
        ensureCellState()
    }

    func ensureCellState() {
        for cell in self.collectionView.visibleCells {
            guard let cell = cell as? GifPickerCell else {
                owsFailDebug("unexpected cell.")
                return
            }
            cell.ensureCellState()
        }
    }

    // MARK: View Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        self.navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel,
                                                                target: self,
                                                                action: #selector(didPressCancel))
        self.navigationItem.title = NSLocalizedString("GIF_PICKER_VIEW_TITLE",
                                                      comment: "Title for the 'GIF picker' dialog.")

        createViews()

        reachability = Reachability.forInternetConnection()
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(reachabilityChanged),
                                               name: NSNotification.Name.reachabilityChanged,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(didBecomeActive),
                                               name: NSNotification.Name.OWSApplicationDidBecomeActive,
                                               object: nil)
        loadTrending()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        guard let navigationBar = navigationController?.navigationBar as? OWSNavigationBar else {
            owsFailDebug("navigationBar was nil or unexpected class")
            return
        }
        navigationBar.switchToStyle(.default)
    }

    var hasEverAppeared = false
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        if !hasEverAppeared {
            searchBar.becomeFirstResponder()
        }
        hasEverAppeared = true
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        progressiveSearchTimer?.invalidate()
        progressiveSearchTimer = nil
    }

    // MARK: Views

    func clearSelectedState() {
        hasSelectedCell = false
        collectionView.isUserInteractionEnabled = true
        selectedMaskingView.isHidden = true
        if let selectedIndices = collectionView.indexPathsForSelectedItems {
            for index in selectedIndices {
                collectionView.deselectItem(at: index, animated: false)
                if let cell = collectionView.cellForItem(at: index) {
                    cell.isSelected = false
                }
            }
        }
    }

    let selectedMaskingView = OWSBezierPathView()

    private func createViews() {

        let backgroundColor = (Theme.isDarkThemeEnabled
            ? UIColor(white: 0.08, alpha: 1.0)
            : Theme.backgroundColor)
        self.view.backgroundColor = backgroundColor

        // Block UIKit from adjust insets of collection view which screws up
        // min/max scroll positions.
        self.automaticallyAdjustsScrollViewInsets = false

        self.collectionView.delegate = self
        self.collectionView.dataSource = self
        self.collectionView.backgroundColor = backgroundColor
        self.collectionView.register(GifPickerCell.self, forCellWithReuseIdentifier: kCellReuseIdentifier)
        view.addSubview(self.collectionView)
        self.collectionView.autoPinEdge(toSuperviewSafeArea: .leading)
        self.collectionView.autoPinEdge(toSuperviewSafeArea: .trailing)

        view.addSubview(selectedMaskingView)
        selectedMaskingView.autoPinEdge(.top, to: .top, of: collectionView)
        selectedMaskingView.autoPinEdge(.leading, to: .leading, of: collectionView)
        selectedMaskingView.autoPinEdge(.trailing, to: .trailing, of: collectionView)
        selectedMaskingView.autoPinEdge(.bottom, to: .bottom, of: collectionView)
        selectedMaskingView.isHidden = true

        // Search
        searchBar.delegate = self
        searchBar.placeholder = NSLocalizedString("GIF_VIEW_SEARCH_PLACEHOLDER_TEXT",
                                                  comment: "Placeholder text for the search field in GIF view")
        view.addSubview(searchBar)
        searchBar.autoPinWidthToSuperview()
        searchBar.autoPin(toTopLayoutGuideOf: self, withInset: 0)
        searchBar.autoPinEdge(.bottom, to: .top, of: collectionView)

        // for iPhoneX devices, extends the black background to the bottom edge of the view.
        let bottomBannerContainer = UIView()
        bottomBannerContainer.backgroundColor = UIColor.black
        self.view.addSubview(bottomBannerContainer)
        bottomBannerContainer.autoPinWidthToSuperview()
        bottomBannerContainer.autoPinEdge(.top, to: .bottom, of: self.collectionView)
        bottomBannerContainer.autoPinEdge(toSuperviewEdge: .bottom)

        let bottomBanner = UIView()
        bottomBannerContainer.addSubview(bottomBanner)

        bottomBanner.autoPinEdge(toSuperviewEdge: .top)
        bottomBanner.autoPinWidthToSuperview()
        self.autoPinView(toBottomOfViewControllerOrKeyboard: bottomBanner, avoidNotch: true)

        // The Giphy API requires us to "show their trademark prominently" in our GIF experience.
        let logoImage = UIImage(named: "giphy_logo")
        let logoImageView = UIImageView(image: logoImage)
        bottomBanner.addSubview(logoImageView)
        logoImageView.autoPinHeightToSuperview(withMargin: 3)
        logoImageView.autoHCenterInSuperview()

        let noResultsView = createErrorLabel(text: NSLocalizedString("GIF_VIEW_SEARCH_NO_RESULTS",
                                                                    comment: "Indicates that the user's search had no results."))
        self.noResultsView = noResultsView
        self.view.addSubview(noResultsView)
        noResultsView.autoPinWidthToSuperview(withMargin: 20)
        noResultsView.autoAlignAxis(.horizontal, toSameAxisOf: self.collectionView)

        let searchErrorView = createErrorLabel(text: NSLocalizedString("GIF_VIEW_SEARCH_ERROR",
                                                                      comment: "Indicates that an error occurred while searching."))
        self.searchErrorView = searchErrorView
        self.view.addSubview(searchErrorView)
        searchErrorView.autoPinWidthToSuperview(withMargin: 20)
        searchErrorView.autoAlignAxis(.horizontal, toSameAxisOf: self.collectionView)

        searchErrorView.isUserInteractionEnabled = true
        searchErrorView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(retryTapped)))

        let activityIndicator = UIActivityIndicatorView(style: .gray)
        self.activityIndicator = activityIndicator
        self.view.addSubview(activityIndicator)
        activityIndicator.autoHCenterInSuperview()
        activityIndicator.autoAlignAxis(.horizontal, toSameAxisOf: self.collectionView)

        self.updateContents()
    }

    private func createErrorLabel(text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.textColor = Theme.primaryTextColor
        label.font = UIFont.ows_semiboldFont(withSize: 20)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        return label
    }

    private func updateContents() {
        guard let noResultsView = self.noResultsView else {
            owsFailDebug("Missing noResultsView")
            return
        }
        guard let searchErrorView = self.searchErrorView else {
            owsFailDebug("Missing searchErrorView")
            return
        }
        guard let activityIndicator = self.activityIndicator else {
            owsFailDebug("Missing activityIndicator")
            return
        }

        switch viewMode {
        case .idle:
            self.collectionView.isHidden = true
            noResultsView.isHidden = true
            searchErrorView.isHidden = true
            activityIndicator.isHidden = true
            activityIndicator.stopAnimating()
        case .searching:
            self.collectionView.isHidden = true
            noResultsView.isHidden = true
            searchErrorView.isHidden = true
            activityIndicator.isHidden = false
            activityIndicator.startAnimating()
        case .results:
            self.collectionView.isHidden = false
            noResultsView.isHidden = true
            searchErrorView.isHidden = true
            activityIndicator.isHidden = true
            activityIndicator.stopAnimating()

            self.collectionView.collectionViewLayout.invalidateLayout()
            self.collectionView.reloadData()
        case .noResults:
            self.collectionView.isHidden = true
            noResultsView.isHidden = false
            searchErrorView.isHidden = true
            activityIndicator.isHidden = true
            activityIndicator.stopAnimating()
        case .error:
            self.collectionView.isHidden = true
            noResultsView.isHidden = true
            searchErrorView.isHidden = false
            activityIndicator.isHidden = true
            activityIndicator.stopAnimating()
        }
    }

    // MARK: - UIScrollViewDelegate

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        self.searchBar.resignFirstResponder()
    }

    // MARK: - UICollectionViewDataSource

    public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return imageInfos.count
    }

    public  func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: kCellReuseIdentifier, for: indexPath)

        guard indexPath.row < imageInfos.count else {
            Logger.warn("indexPath: \(indexPath.row) out of range for imageInfo count: \(imageInfos.count) ")
            return cell
        }
        let imageInfo = imageInfos[indexPath.row]

        guard let gifCell = cell as? GifPickerCell else {
            owsFailDebug("Unexpected cell type.")
            return cell
        }
        gifCell.imageInfo = imageInfo
        return cell
    }

    // MARK: - UICollectionViewDelegate

    public func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        guard let cell = collectionView.cellForItem(at: indexPath) as? GifPickerCell else {
            owsFailDebug("unexpected cell.")
            return false
        }

        guard cell.stillAsset != nil || cell.animatedAsset != nil else {
            // we don't want to let the user blindly select a gray cell
            Logger.debug("ignoring selection of cell with no preview")
            return false
        }

        guard self.hasSelectedCell == false else {
            owsFailDebug("Already selected cell")
            return false
        }

        return true
    }

    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {

        guard let cell = collectionView.cellForItem(at: indexPath) as? GifPickerCell else {
            owsFailDebug("unexpected cell.")
            return
        }

        guard cell.stillAsset != nil || cell.animatedAsset != nil else {
            // we don't want to let the user blindly select a gray cell
            Logger.debug("ignoring selection of cell with no preview")
            return
        }

        guard self.hasSelectedCell == false else {
            owsFailDebug("Already selected cell")
            return
        }
        self.hasSelectedCell = true

        // Fade out all cells except the selected one.
        let cellRect = collectionView.convert(cell.frame, to: selectedMaskingView)
        selectedMaskingView.configureShapeLayerBlock = { layer, bounds in
            let path = UIBezierPath(rect: bounds)
            path.append(UIBezierPath(rect: cellRect))

            layer.path = path.cgPath
            layer.fillRule = .evenOdd
            layer.fillColor = UIColor.black.cgColor
            layer.opacity = 0.7
        }
        selectedMaskingView.isHidden = false

        cell.isSelected = true
        self.collectionView.isUserInteractionEnabled = false

        getFileForCell(cell)
    }

    public func getFileForCell(_ cell: GifPickerCell) {
        enum GetFileError: Error {
            case noLongerRelevant
        }

        GiphyDownloader.giphyDownloader.cancelAllRequests()

        firstly {
            cell.requestRenditionForSending()
        }.map(on: .global()) { [weak self] (asset: ProxiedContentAsset) -> SignalAttachment in
            guard let _ = self else { throw GetFileError.noLongerRelevant }

            guard let rendition = asset.assetDescription as? GiphyRendition else {
                throw OWSAssertionError("Invalid asset description.")
            }

            let pathForCachedAsset = asset.filePath
            let pathForConsumableFile = OWSFileSystem.temporaryFilePath(withFileExtension: "gif")
            try FileManager.default.copyItem(atPath: pathForCachedAsset, toPath: pathForConsumableFile)
            let dataSource = try DataSourcePath.dataSource(withFilePath: pathForConsumableFile,
                                                           shouldDeleteOnDeallocation: false)

            return SignalAttachment.attachment(dataSource: dataSource, dataUTI: rendition.utiType, imageQuality: .original)
        }.done { [weak self] attachment in
            guard let self = self else {
                throw GetFileError.noLongerRelevant
            }

            self.delegate?.gifPickerDidSelect(attachment: attachment)
        }.catch { [weak self] error in
            guard let self = self else {
                Logger.info("ignoring failure, since VC was dismissed before fetching finished.")
                return
            }

            let alert = ActionSheetController(title: NSLocalizedString("GIF_PICKER_FAILURE_ALERT_TITLE", comment: "Shown when selected GIF couldn't be fetched"),
                                          message: error.localizedDescription)
            alert.addAction(ActionSheetAction(title: CommonStrings.retryButton, style: .default) { _ in
                self.getFileForCell(cell)
            })
            alert.addAction(ActionSheetAction(title: CommonStrings.dismissButton, style: .cancel) { _ in
                self.delegate?.gifPickerDidCancel()
            })

            self.presentActionSheet(alert)
        }.retainUntilComplete()
    }

    public func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        guard let cell = cell as? GifPickerCell else {
            owsFailDebug("unexpected cell.")
            return
        }
        // We only want to load the cells which are on-screen.
        cell.isCellVisible = true
    }

    public func collectionView(_ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        guard let cell = cell as? GifPickerCell else {
            owsFailDebug("unexpected cell.")
            return
        }
        cell.isCellVisible = false
    }

    // MARK: - Event Handlers

    @objc func didPressCancel(sender: UIButton) {
        delegate?.gifPickerDidCancel()
    }

    // MARK: - UISearchBarDelegate

    public func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        // Clear error messages immediately.
        if viewMode == .error || viewMode == .noResults {
            viewMode = .idle
        }

        // Do progressive search after a delay.
        progressiveSearchTimer?.invalidate()
        progressiveSearchTimer = nil
        let kProgressiveSearchDelaySeconds = 1.0
        progressiveSearchTimer = WeakTimer.scheduledTimer(timeInterval: kProgressiveSearchDelaySeconds, target: self, userInfo: nil, repeats: true) { [weak self] _ in
            guard let strongSelf = self else {
                return
            }

            strongSelf.tryToSearch()
        }
    }

    public func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        self.searchBar.resignFirstResponder()

        tryToSearch()
    }

    public func tryToSearch() {
        progressiveSearchTimer?.invalidate()
        progressiveSearchTimer = nil

        guard let text = searchBar.text else {
            OWSActionSheets.showErrorAlert(message: NSLocalizedString("GIF_PICKER_VIEW_MISSING_QUERY",
                                                           comment: "Alert message shown when user tries to search for GIFs without entering any search terms."))
            return
        }

        let query = (text as String).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

        if (viewMode == .searching || viewMode == .results) && lastQuery == query {
            Logger.info("ignoring duplicate search: \(query)")
            return
        }

        search(query: query)
    }

    private func loadTrending() {
        assert(progressiveSearchTimer == nil)
        assert(searchBar.text == nil || searchBar.text?.count == 0)
        assert(lastQuery == nil)

        giphyAPI.trending().done { [weak self] imageInfos in
            guard let self = self else { return }

            guard self.lastQuery == nil else {
                Logger.info("not showing trending results due to subsequent searche")
                return
            }

            Logger.info("showing trending")
            if imageInfos.count > 0 {
                self.imageInfos = imageInfos
                self.viewMode = .results
            } else {
                owsFailDebug("trending results was unexpectedly empty")
            }
        }.catch { error in
            // Don't both showing error UI feedback for default "trending" results.
            Logger.error("error: \(error)")
        }.retainUntilComplete()
    }

    private func search(query: String) {
        Logger.info("searching: \(query)")

        progressiveSearchTimer?.invalidate()
        progressiveSearchTimer = nil
        imageInfos = []
        viewMode = .searching
        lastQuery = query
        self.collectionView.contentOffset = CGPoint.zero

        giphyAPI.search(query: query, success: { [weak self] imageInfos in
            guard let strongSelf = self else { return }
            Logger.info("search complete")
            strongSelf.imageInfos = imageInfos
            if imageInfos.count > 0 {
                strongSelf.viewMode = .results
            } else {
                strongSelf.viewMode = .noResults
            }
        },
            failure: { [weak self] _ in
                guard let strongSelf = self else { return }
                Logger.info("search failed.")
                // TODO: Present this error to the user.
                strongSelf.viewMode = .error
        })
    }

    // MARK: - GifPickerLayoutDelegate

    func imageInfosForLayout() -> [GiphyImageInfo] {
        return imageInfos
    }

    // MARK: - Event Handlers

    @objc func retryTapped(sender: UIGestureRecognizer) {
        guard sender.state == .recognized else {
            return
        }
        guard viewMode == .error else {
            return
        }
        tryToSearch()
    }

    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        layout.invalidateLayout()
    }
}
