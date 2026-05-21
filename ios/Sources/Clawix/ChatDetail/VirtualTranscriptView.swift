import SwiftUI
import UIKit

struct VirtualTranscriptRow: Identifiable, Equatable {
    enum Kind: Equatable {
        case loadingOlder
        case loadingPlaceholder
        case emptyPlaceholder
        case message(String)
        case spacer(CGFloat)
        case tail
    }

    let id: String
    let kind: Kind
    let estimatedHeight: CGFloat
    let retainsOverscan: Bool

    static func loadingOlder() -> VirtualTranscriptRow {
        VirtualTranscriptRow(
            id: "__loading_older__",
            kind: .loadingOlder,
            estimatedHeight: 28,
            retainsOverscan: false
        )
    }

    static func loadingPlaceholder() -> VirtualTranscriptRow {
        VirtualTranscriptRow(
            id: "__loading_placeholder__",
            kind: .loadingPlaceholder,
            estimatedHeight: 140,
            retainsOverscan: false
        )
    }

    static func emptyPlaceholder() -> VirtualTranscriptRow {
        VirtualTranscriptRow(
            id: "__empty_placeholder__",
            kind: .emptyPlaceholder,
            estimatedHeight: 140,
            retainsOverscan: false
        )
    }

    static func spacer(id: String, height: CGFloat) -> VirtualTranscriptRow {
        VirtualTranscriptRow(
            id: id,
            kind: .spacer(height),
            estimatedHeight: height,
            retainsOverscan: false
        )
    }

    static func tail(id: String) -> VirtualTranscriptRow {
        VirtualTranscriptRow(
            id: id,
            kind: .tail,
            estimatedHeight: 1,
            retainsOverscan: false
        )
    }
}

struct VirtualTranscriptMetrics: Equatable {
    let content: CGFloat
    let container: CGFloat
    let insets: CGFloat
    let offsetY: CGFloat
}

struct VirtualTranscriptView<RowContent: View>: UIViewRepresentable {
    let rows: [VirtualTranscriptRow]
    let tailId: String
    @Binding var bottomId: String?
    let onMetricsChange: (VirtualTranscriptMetrics) -> Void
    let onNearTop: () -> Void
    let onRowVisible: (VirtualTranscriptRow) -> Void
    let rowContent: (VirtualTranscriptRow) -> RowContent

    init(
        rows: [VirtualTranscriptRow],
        tailId: String,
        bottomId: Binding<String?>,
        onMetricsChange: @escaping (VirtualTranscriptMetrics) -> Void,
        onNearTop: @escaping () -> Void,
        onRowVisible: @escaping (VirtualTranscriptRow) -> Void,
        @ViewBuilder rowContent: @escaping (VirtualTranscriptRow) -> RowContent
    ) {
        self.rows = rows
        self.tailId = tailId
        self._bottomId = bottomId
        self.onMetricsChange = onMetricsChange
        self.onNearTop = onNearTop
        self.onRowVisible = onRowVisible
        self.rowContent = rowContent
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UICollectionView {
        let layout = UICollectionViewCompositionalLayout { _, _ in
            let itemSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1),
                heightDimension: .estimated(96)
            )
            let item = NSCollectionLayoutItem(layoutSize: itemSize)
            let group = NSCollectionLayoutGroup.vertical(
                layoutSize: itemSize,
                subitems: [item]
            )
            let section = NSCollectionLayoutSection(group: group)
            section.interGroupSpacing = 22
            section.contentInsets = NSDirectionalEdgeInsets(
                top: 0,
                leading: 20,
                bottom: 0,
                trailing: 20
            )
            return section
        }

        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .clear
        collectionView.alwaysBounceVertical = true
        collectionView.showsVerticalScrollIndicator = false
        collectionView.keyboardDismissMode = .interactive
        collectionView.dataSource = context.coordinator
        collectionView.delegate = context.coordinator
        collectionView.prefetchDataSource = context.coordinator
        collectionView.register(
            TranscriptHostingCell.self,
            forCellWithReuseIdentifier: TranscriptHostingCell.reuseIdentifier
        )
        context.coordinator.collectionView = collectionView
        return collectionView
    }

    func updateUIView(_ collectionView: UICollectionView, context: Context) {
        context.coordinator.update(parent: self, in: collectionView)
    }

    final class Coordinator: NSObject,
        UICollectionViewDataSource,
        UICollectionViewDelegate,
        UICollectionViewDataSourcePrefetching
    {
        var parent: VirtualTranscriptView
        weak var collectionView: UICollectionView?

        private var measuredHeights: [String: CGFloat] = [:]
        private var didInitialLoad = false
        private var lastRequestedBottomGeneration = 0
        private var contentGeneration = 0

        init(parent: VirtualTranscriptView) {
            self.parent = parent
            super.init()
        }

        func update(parent: VirtualTranscriptView, in collectionView: UICollectionView) {
            let oldRows = self.parent.rows
            let oldAtTail = isAtTail(collectionView)
            let anchor = oldAtTail ? nil : visibleAnchor(in: collectionView)

            self.parent = parent
            let rowsChanged = oldRows != parent.rows
            if !didInitialLoad || rowsChanged {
                didInitialLoad = true
                contentGeneration &+= 1
                collectionView.reloadData()
                collectionView.collectionViewLayout.invalidateLayout()
                collectionView.layoutIfNeeded()
            }

            if parent.bottomId == parent.tailId {
                if oldAtTail || rowsChanged || lastRequestedBottomGeneration != contentGeneration {
                    scrollToTail(collectionView, animated: false)
                    lastRequestedBottomGeneration = contentGeneration
                }
            } else if let anchor, rowsChanged {
                restore(anchor: anchor, in: collectionView)
            }

            reportMetrics(collectionView)
        }

        func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
            parent.rows.count
        }

        func collectionView(
            _ collectionView: UICollectionView,
            cellForItemAt indexPath: IndexPath
        ) -> UICollectionViewCell {
            guard let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: TranscriptHostingCell.reuseIdentifier,
                for: indexPath
            ) as? TranscriptHostingCell else {
                return UICollectionViewCell()
            }
            let row = parent.rows[indexPath.item]
            cell.configure(
                row: row,
                content: AnyView(
                    parent.rowContent(row)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .onGeometryChange(for: CGFloat.self) { proxy in
                            proxy.size.height
                        } action: { [weak self] _, height in
                            self?.record(height: height, for: row.id)
                        }
                )
            )
            return cell
        }

        func collectionView(
            _ collectionView: UICollectionView,
            willDisplay cell: UICollectionViewCell,
            forItemAt indexPath: IndexPath
        ) {
            guard parent.rows.indices.contains(indexPath.item) else { return }
            parent.onRowVisible(parent.rows[indexPath.item])
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard let collectionView = scrollView as? UICollectionView else { return }
            reportMetrics(collectionView)

            let nextBottomId = isAtTail(collectionView) ? parent.tailId : nil
            if parent.bottomId != nextBottomId {
                parent.bottomId = nextBottomId
            }

            if scrollView.contentOffset.y < ChatDetailView.loadOlderThreshold,
               scrollView.contentSize.height > scrollView.bounds.height + 1 {
                parent.onNearTop()
            }
        }

        func collectionView(
            _ collectionView: UICollectionView,
            prefetchItemsAt indexPaths: [IndexPath]
        ) {
            for indexPath in indexPaths {
                guard parent.rows.indices.contains(indexPath.item) else { continue }
                let row = parent.rows[indexPath.item]
                if row.retainsOverscan {
                    parent.onRowVisible(row)
                }
            }
        }

        private func record(height: CGFloat, for id: String) {
            guard height.isFinite, height > 0 else { return }
            let previous = measuredHeights[id] ?? 0
            guard abs(previous - height) > 0.5 else { return }
            measuredHeights[id] = height
        }

        private func reportMetrics(_ collectionView: UICollectionView) {
            parent.onMetricsChange(
                VirtualTranscriptMetrics(
                    content: collectionView.contentSize.height,
                    container: collectionView.bounds.height,
                    insets: collectionView.adjustedContentInset.top
                        + collectionView.adjustedContentInset.bottom,
                    offsetY: collectionView.contentOffset.y
                )
            )
        }

        private func isAtTail(_ collectionView: UICollectionView) -> Bool {
            guard collectionView.contentSize.height > 0 else { return true }
            let visibleBottom = collectionView.contentOffset.y
                + collectionView.bounds.height
                - collectionView.adjustedContentInset.bottom
            return visibleBottom >= collectionView.contentSize.height - 8
        }

        private func scrollToTail(_ collectionView: UICollectionView, animated: Bool) {
            guard let index = parent.rows.firstIndex(where: { $0.id == parent.tailId }) else { return }
            collectionView.scrollToItem(
                at: IndexPath(item: index, section: 0),
                at: .bottom,
                animated: animated
            )
        }

        private func visibleAnchor(in collectionView: UICollectionView) -> VisibleAnchor? {
            let visibleTop = collectionView.contentOffset.y + collectionView.adjustedContentInset.top
            let attrs = collectionView.indexPathsForVisibleItems
                .compactMap { collectionView.layoutAttributesForItem(at: $0) }
                .filter { parent.rows.indices.contains($0.indexPath.item) }
                .sorted { lhs, rhs in
                    if lhs.frame.minY == rhs.frame.minY {
                        return lhs.indexPath.item < rhs.indexPath.item
                    }
                    return lhs.frame.minY < rhs.frame.minY
                }
            guard let first = attrs.first else { return nil }
            let row = parent.rows[first.indexPath.item]
            return VisibleAnchor(id: row.id, offset: visibleTop - first.frame.minY)
        }

        private func restore(anchor: VisibleAnchor, in collectionView: UICollectionView) {
            guard let index = parent.rows.firstIndex(where: { $0.id == anchor.id }) else { return }
            collectionView.layoutIfNeeded()
            guard let attrs = collectionView.layoutAttributesForItem(
                at: IndexPath(item: index, section: 0)
            ) else { return }
            let y = attrs.frame.minY + anchor.offset - collectionView.adjustedContentInset.top
            collectionView.setContentOffset(
                CGPoint(x: collectionView.contentOffset.x, y: max(-collectionView.adjustedContentInset.top, y)),
                animated: false
            )
        }
    }
}

private struct VisibleAnchor {
    let id: String
    let offset: CGFloat
}

private final class TranscriptHostingCell: UICollectionViewCell {
    static let reuseIdentifier = "TranscriptHostingCell"

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        contentView.backgroundColor = .clear
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(row: VirtualTranscriptRow, content: AnyView) {
        accessibilityIdentifier = "transcript-row-\(row.id)"
        contentConfiguration = UIHostingConfiguration {
            content
        }
        .margins(.all, 0)
    }
}
