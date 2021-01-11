//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import PromiseKit

public protocol GalleryRailItemProvider: class {
    var railItems: [GalleryRailItem] { get }
}

public protocol GalleryRailItem {
    func buildRailItemView() -> UIView
    func isEqualToGalleryRailItem(_ other: GalleryRailItem?) -> Bool
}

public extension GalleryRailItem where Self: Equatable {
    func isEqualToGalleryRailItem(_ other: GalleryRailItem?) -> Bool {
        guard let other = other as? Self else {
            return false
        }
        return self == other
    }
}

protocol GalleryRailCellViewDelegate: class {
    func didTapGalleryRailCellView(_ galleryRailCellView: GalleryRailCellView)
}

public class GalleryRailCellView: UIView {

    weak var delegate: GalleryRailCellViewDelegate?

    override init(frame: CGRect) {
        super.init(frame: frame)

        layoutMargins = .zero
        clipsToBounds = false
        addSubview(contentContainer)
        contentContainer.autoPinEdgesToSuperviewMargins()
        contentContainer.layer.cornerRadius = 4.8

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(didTap(sender:)))
        addGestureRecognizer(tapGesture)
    }

    public required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Actions

    @objc
    func didTap(sender: UITapGestureRecognizer) {
        self.delegate?.didTapGalleryRailCellView(self)
    }

    // MARK: 

    var item: GalleryRailItem?

    func configure(item: GalleryRailItem, delegate: GalleryRailCellViewDelegate) {
        self.item = item
        self.delegate = delegate

        for view in contentContainer.subviews {
            view.removeFromSuperview()
        }

        let itemView = item.buildRailItemView()
        contentContainer.addSubview(itemView)
        itemView.autoPinEdgesToSuperviewEdges()
    }

    // MARK: Selected

    private(set) var isSelected: Bool = false

    public let cellBorderWidth: CGFloat = 3

    func setIsSelected(_ isSelected: Bool) {
        self.isSelected = isSelected

        // Reserve space for the selection border whether or not the cell is selected.
        layoutMargins = UIEdgeInsets(top: 0, left: cellBorderWidth, bottom: 0, right: cellBorderWidth)

        if isSelected {
            contentContainer.layer.borderColor = Theme.galleryHighlightColor.cgColor
            contentContainer.layer.borderWidth = cellBorderWidth
        } else {
            contentContainer.layer.borderWidth = 0
        }
    }

    // MARK: Subview Helpers

    let contentContainer: UIView = {
        let view = UIView()
        view.autoPinToSquareAspectRatio()
        view.clipsToBounds = true

        return view
    }()
}

public protocol GalleryRailViewDelegate: class {
    func galleryRailView(_ galleryRailView: GalleryRailView, didTapItem imageRailItem: GalleryRailItem)
}

public class GalleryRailView: UIView, GalleryRailCellViewDelegate {

    public weak var delegate: GalleryRailViewDelegate?

    public var cellViews: [GalleryRailCellView] = []

    var cellViewItems: [GalleryRailItem] {
        get { return cellViews.compactMap { $0.item } }
    }

    // MARK: Initializers

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = false
        addSubview(scrollView)
        scrollView.clipsToBounds = false
        scrollView.layoutMargins = .zero
        scrollView.autoPinEdgesToSuperviewMargins()
    }

    public required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Public

    typealias AnimationBlock = () -> Void
    typealias AnimationCompletionBlock = (Bool) -> Void

    // UIView.animate(), takes an "animated" flag which disables animations.
    private func animate(animationDuration: TimeInterval,
                         animated: Bool,
                         animations: @escaping AnimationBlock,
                         completion: AnimationCompletionBlock? = nil) {
        guard animated else {
            animations()
            completion?(true)
            return
        }
        UIView.animate(withDuration: animationDuration, animations: animations, completion: completion)
    }

    public func configureCellViews(itemProvider: GalleryRailItemProvider?, focusedItem: GalleryRailItem?, cellViewBuilder: (GalleryRailItem) -> GalleryRailCellView, animated: Bool = true) {
        let animationDuration: TimeInterval = 0.2

        guard let itemProvider = itemProvider else {
            animate(animationDuration: animationDuration,
                    animated: animated,
                    animations: {
                self.isHidden = true
            })
            self.cellViews = []
            return
        }

        let areRailItemsIdentical = { (lhs: [GalleryRailItem], rhs: [GalleryRailItem]) -> Bool in
            guard lhs.count == rhs.count else {
                return false
            }
            for (index, element) in lhs.enumerated() {
                guard element.isEqualToGalleryRailItem(rhs[index]) else {
                    return false
                }
            }
            return true
        }

        if itemProvider === self.itemProvider, areRailItemsIdentical(itemProvider.railItems, self.cellViewItems) {
            animate(animationDuration: animationDuration,
                    animated: animated,
                    animations: {
                self.updateFocusedItem(focusedItem)
                self.layoutIfNeeded()
            })
        }

        self.itemProvider = itemProvider

        guard itemProvider.railItems.count > 1 else {
            let cellViews = scrollView.subviews

            animate(animationDuration: animationDuration, animated: animated,
                           animations: {
                            cellViews.forEach { $0.isHidden = true }
                            self.isHidden = true
            },
                           completion: { _ in cellViews.forEach { $0.removeFromSuperview() } })
            self.cellViews = []
            return
        }

        scrollView.subviews.forEach { $0.removeFromSuperview() }

        let animatedReveal: Bool
        if #available(iOS 12, *) {
            animatedReveal = true
        } else {
            // This animation is broken on iOS11
            // Often times the media rail will "drop in" from the top of the screen
            // rather than growing from the top of the toolbar. It's better to skip this
            // animation all together.
            animatedReveal = false
        }
        animate(animationDuration: animationDuration,
                animated: animatedReveal,
                animations: {
            self.isHidden = false
        })

        let cellViews = buildCellViews(items: itemProvider.railItems, cellViewBuilder: cellViewBuilder)
        self.cellViews = cellViews
        let stackView = UIStackView(arrangedSubviews: cellViews)
        stackView.axis = .horizontal
        stackView.spacing = 0
        stackView.clipsToBounds = false

        scrollView.addSubview(stackView)
        stackView.autoPinEdgesToSuperviewEdges()
        stackView.autoMatch(.height, to: .height, of: scrollView)

        updateFocusedItem(focusedItem)
    }

    // MARK: GalleryRailCellViewDelegate

    func didTapGalleryRailCellView(_ galleryRailCellView: GalleryRailCellView) {
        guard let item = galleryRailCellView.item else {
            owsFailDebug("item was unexpectedly nil")
            return
        }

        delegate?.galleryRailView(self, didTapItem: item)
    }

    // MARK: Subview Helpers

    private var itemProvider: GalleryRailItemProvider?

    private let scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.isScrollEnabled = true
        return scrollView
    }()

    private func buildCellViews(items: [GalleryRailItem], cellViewBuilder: (GalleryRailItem) -> GalleryRailCellView) -> [GalleryRailCellView] {
        return items.map { item in
            let cellView = cellViewBuilder(item)
            cellView.configure(item: item, delegate: self)
            return cellView
        }
    }

    enum ScrollFocusMode {
        case keepCentered, keepWithinBounds
    }
    var scrollFocusMode: ScrollFocusMode = .keepCentered
    func updateFocusedItem(_ focusedItem: GalleryRailItem?) {
        var selectedCellView: GalleryRailCellView?
        cellViews.forEach { cellView in
            if let item = cellView.item, item.isEqualToGalleryRailItem(focusedItem) {
                assert(selectedCellView == nil)
                selectedCellView = cellView
                cellView.setIsSelected(true)
            } else {
                cellView.setIsSelected(false)
            }
        }

        self.layoutIfNeeded()
        switch scrollFocusMode {
        case .keepCentered:
            guard let selectedCell = selectedCellView else {
                owsFailDebug("selectedCell was unexpectedly nil")
                return
            }

            let cellViewCenter = selectedCell.superview!.convert(selectedCell.center, to: scrollView)
            let additionalInset = scrollView.center.x - cellViewCenter.x

            var inset = scrollView.contentInset
            inset.left = additionalInset
            scrollView.contentInset = inset

            var offset = scrollView.contentOffset
            offset.x = -additionalInset
            scrollView.contentOffset = offset
        case .keepWithinBounds:
            guard let selectedCell = selectedCellView else {
                owsFailDebug("selectedCell was unexpectedly nil")
                return
            }

            let cellFrame = selectedCell.superview!.convert(selectedCell.frame, to: scrollView)

            scrollView.scrollRectToVisible(cellFrame, animated: true)
        }
    }
}
