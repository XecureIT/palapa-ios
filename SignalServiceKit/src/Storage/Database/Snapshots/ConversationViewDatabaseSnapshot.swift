//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import GRDB

@objc
public protocol ConversationViewDatabaseSnapshotDelegate: AnyObject {
    func conversationViewDatabaseSnapshotWillUpdate()
    func conversationViewDatabaseSnapshotDidUpdate(transactionChanges: ConversationViewDatabaseTransactionChanges)
    func conversationViewDatabaseSnapshotDidUpdateExternally()
    func conversationViewDatabaseSnapshotDidReset()
}

@objc
public class ConversationViewDatabaseObserver: NSObject {

    private var _snapshotDelegates: [Weak<ConversationViewDatabaseSnapshotDelegate>] = []
    private var snapshotDelegates: [ConversationViewDatabaseSnapshotDelegate] {
        return _snapshotDelegates.compactMap { $0.value }
    }

    @objc
    public func appendSnapshotDelegate(_ snapshotDelegate: ConversationViewDatabaseSnapshotDelegate) {
        _snapshotDelegates = _snapshotDelegates.filter { $0.value != nil} + [Weak(value: snapshotDelegate)]
    }

    // internal - should only be called by DatabaseStorage
    func didTouch(interaction: TSInteraction, transaction: GRDBWriteTransaction) {
        // Note: We don't actually use the `transaction` param, but touching must happen within
        // a write transaction in order for the touch machinery to notify it's observers
        // in the expected way.
        AssertIsOnUIDatabaseObserverSerialQueue()
        let rowId = RowId(interaction.sortId)
        assert(rowId > 0)
        pendingInteractionChanges.insert(rowId)

        let interactionThread: TSThread? = interaction.thread(transaction: transaction.asAnyRead)
        if let thread = interactionThread {
            didTouch(thread: thread, transaction: transaction)
        } else {
            owsFailDebug("Could not load thread for interaction.")
        }
    }

    // internal - should only be called by DatabaseStorage
    func didTouch(thread: TSThread, transaction: GRDBWriteTransaction) {
        // Note: We don't actually use the `transaction` param, but touching must happen within
        // a write transaction in order for the touch machinery to notify it's observers
        // in the expected way.
        AssertIsOnUIDatabaseObserverSerialQueue()

        guard let grdbId = thread.grdbId else {
            owsFailDebug("Missing grdbId.")
            return
        }

        pendingThreadChanges.insert(grdbId.int64Value)
    }

    private typealias RowId = Int64

    private var _pendingInteractionChanges: Set<RowId> = Set()
    private var pendingInteractionChanges: Set<RowId> {
        get {
            AssertIsOnUIDatabaseObserverSerialQueue()
            return _pendingInteractionChanges
        }
        set {
            AssertIsOnUIDatabaseObserverSerialQueue()
            _pendingInteractionChanges = newValue
        }
    }

    private var _committedInteractionChanges: Set<RowId>?
    private var committedInteractionChanges: Set<RowId>? {
        get {
            AssertIsOnMainThread()
            return _committedInteractionChanges
        }
        set {
            AssertIsOnMainThread()
            _committedInteractionChanges = newValue
        }
    }

    private var _pendingThreadChanges: Set<RowId> = Set()
    private var pendingThreadChanges: Set<RowId> {
        get {
            AssertIsOnUIDatabaseObserverSerialQueue()
            return _pendingThreadChanges
        }
        set {
            AssertIsOnUIDatabaseObserverSerialQueue()
            _pendingThreadChanges = newValue
        }
    }

    private var _committedThreadChanges: Set<RowId>?
    private var committedThreadChanges: Set<RowId>? {
        get {
            AssertIsOnMainThread()
            return _committedThreadChanges
        }
        set {
            AssertIsOnMainThread()
            _committedThreadChanges = newValue
        }
    }
}

@objc
public class ConversationViewDatabaseTransactionChanges: NSObject {
    private let updatedRowIds: Set<Int64>
    private let updatedThreadIds: Set<Int64>

    init(updatedRowIds: Set<Int64>, updatedThreadIds: Set<Int64>) throws {
        guard updatedRowIds.count < UIDatabaseObserver.kMaxIncrementalRowChanges else {
            throw DatabaseObserverError.changeTooLarge
        }

        self.updatedRowIds = updatedRowIds
        self.updatedThreadIds = updatedThreadIds
    }

    @objc
    public func updatedInteractionIds(forThreadId threadUniqueId: String, transaction: GRDBReadTransaction) throws -> Set<String> {
        guard updatedRowIds.count > 0 else {
            return Set()
        }

        guard updatedRowIds.count < UIDatabaseObserver.kMaxIncrementalRowChanges else {
            owsFailDebug("updatedRowIds count should be enforced in initializer")
            throw DatabaseObserverError.changeTooLarge
        }

        let commaSeparatedRowIds = updatedRowIds.map { String($0) }.joined(separator: ", ")
        let rowIdsSQL = "(\(commaSeparatedRowIds))"
        // GRDB TODO: I don't think we need to filter by threadUniqueId here.
        let sql = """
        SELECT \(interactionColumn: .uniqueId)
        FROM \(InteractionRecord.databaseTableName)
        WHERE rowid IN \(rowIdsSQL)
        AND \(interactionColumn: .threadUniqueId) = ?
        """

        let uniqueIds = try String.fetchAll(transaction.database, sql: sql, arguments: [threadUniqueId])

        return Set(uniqueIds)
    }

    @objc(containsThreadRowId:)
    public func contains(threadRowId: NSNumber) -> Bool {
        return updatedThreadIds.contains(threadRowId.int64Value)
    }
}

extension ConversationViewDatabaseObserver: DatabaseSnapshotDelegate {

    // MARK: - Transaction LifeCycle

    public func snapshotTransactionDidChange(with event: DatabaseEvent) {
        Logger.verbose("")
        AssertIsOnUIDatabaseObserverSerialQueue()
        if event.tableName == InteractionRecord.databaseTableName {
            _ = pendingInteractionChanges.insert(event.rowID)
        } else if event.tableName == ThreadRecord.databaseTableName {
            _ = pendingThreadChanges.insert(event.rowID)
        }
    }

    public func snapshotTransactionDidCommit(db: Database) {
        AssertIsOnUIDatabaseObserverSerialQueue()
        let pendingInteractionChanges = self.pendingInteractionChanges
        self.pendingInteractionChanges = Set()
        let pendingThreadChanges = self.pendingThreadChanges
        self.pendingThreadChanges = Set()

        DispatchQueue.main.async {
            self.committedInteractionChanges = pendingInteractionChanges
            self.committedThreadChanges = pendingThreadChanges
        }
    }

    public func snapshotTransactionDidRollback(db: Database) {
        owsFailDebug("we should verify this works if we ever start to use rollbacks")
        AssertIsOnUIDatabaseObserverSerialQueue()
        pendingInteractionChanges = Set()
        pendingThreadChanges = Set()
    }

    // MARK: - Snapshot LifeCycle (Post Commit)

    public func databaseSnapshotWillUpdate() {
        AssertIsOnMainThread()
        for delegate in snapshotDelegates {
            delegate.conversationViewDatabaseSnapshotWillUpdate()
        }
    }

    public func databaseSnapshotDidUpdate() {
        AssertIsOnMainThread()
        do {
            guard let committedInteractionChanges = self.committedInteractionChanges else {
                throw OWSErrorMakeAssertionError("committedInteractionChanges were unexpectedly nil")
            }
            self.committedInteractionChanges = nil

            guard let committedThreadChanges = self.committedThreadChanges else {
                throw OWSErrorMakeAssertionError("committedThreadChanges was unexpectedly nil")
            }
            self.committedThreadChanges = nil

            let transactionChanges = try ConversationViewDatabaseTransactionChanges(updatedRowIds: committedInteractionChanges,
                                                                                    updatedThreadIds: committedThreadChanges)
            for delegate in snapshotDelegates {
                delegate.conversationViewDatabaseSnapshotDidUpdate(transactionChanges: transactionChanges)
            }
        } catch DatabaseObserverError.changeTooLarge {
            for delegate in snapshotDelegates {
                delegate.conversationViewDatabaseSnapshotDidReset()
            }
        } catch {
            owsFailDebug("unknown error: \(error)")
            for delegate in snapshotDelegates {
                delegate.conversationViewDatabaseSnapshotDidReset()
            }
        }
    }

    public func databaseSnapshotDidUpdateExternally() {
        AssertIsOnMainThread()
        for delegate in snapshotDelegates {
            delegate.conversationViewDatabaseSnapshotDidUpdateExternally()
        }
    }
}
