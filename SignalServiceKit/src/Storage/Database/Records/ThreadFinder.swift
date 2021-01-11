//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import GRDB

public protocol ThreadFinder {
    associatedtype ReadTransaction

    func visibleThreadCount(isArchived: Bool, transaction: ReadTransaction) throws -> UInt
    func enumerateVisibleThreads(isArchived: Bool, transaction: ReadTransaction, block: @escaping (TSThread) -> Void) throws
    func sortIndex(thread: TSThread, transaction: ReadTransaction) throws -> UInt?
}

@objc
public class AnyThreadFinder: NSObject, ThreadFinder {
    public typealias ReadTransaction = SDSAnyReadTransaction

    let grdbAdapter: GRDBThreadFinder = GRDBThreadFinder()
    let yapAdapter: YAPDBThreadFinder = YAPDBThreadFinder()

    public func visibleThreadCount(isArchived: Bool, transaction: SDSAnyReadTransaction) throws -> UInt {
        switch transaction.readTransaction {
        case .grdbRead(let grdb):
            return try grdbAdapter.visibleThreadCount(isArchived: isArchived, transaction: grdb)
        case .yapRead(let yap):
            return yapAdapter.visibleThreadCount(isArchived: isArchived, transaction: yap)
        }
    }

    @objc
    public func enumerateVisibleThreads(isArchived: Bool, transaction: SDSAnyReadTransaction, block: @escaping (TSThread) -> Void) throws {
        switch transaction.readTransaction {
        case .grdbRead(let grdb):
            try grdbAdapter.enumerateVisibleThreads(isArchived: isArchived, transaction: grdb, block: block)
        case .yapRead(let yap):
            yapAdapter.enumerateVisibleThreads(isArchived: isArchived, transaction: yap, block: block)
        }
    }

    @objc
    public func sortIndexObjc(thread: TSThread, transaction: ReadTransaction) -> NSNumber? {
        do {
            guard let value = try sortIndex(thread: thread, transaction: transaction) else {
                return nil
            }
            return NSNumber(value: value)
        } catch {
            owsFailDebug("error: \(error)")
            return nil
        }
    }

    public func sortIndex(thread: TSThread, transaction: SDSAnyReadTransaction) throws -> UInt? {
        switch transaction.readTransaction {
        case .grdbRead(let grdb):
            return try grdbAdapter.sortIndex(thread: thread, transaction: grdb)
        case .yapRead(let yap):
            return yapAdapter.sortIndex(thread: thread, transaction: yap)
        }
    }
}

struct YAPDBThreadFinder: ThreadFinder {
    typealias ReadTransaction = YapDatabaseReadTransaction

    func visibleThreadCount(isArchived: Bool, transaction: YapDatabaseReadTransaction) -> UInt {
        guard let view = ext(transaction) else {
            return 0
        }
        return view.numberOfItems(inGroup: group(isArchived: isArchived))
    }

    func enumerateVisibleThreads(isArchived: Bool, transaction: YapDatabaseReadTransaction, block: @escaping (TSThread) -> Void) {
        guard let view = ext(transaction) else {
            return
        }
        view.safe_enumerateKeysAndObjects(inGroup: group(isArchived: isArchived),
                                          extensionName: type(of: self).extensionName,
                                          with: NSEnumerationOptions.reverse) { _, _, object, _, _ in
                                            guard let thread = object as? TSThread else {
                                                owsFailDebug("unexpected object: \(type(of: object))")
                                                return
                                            }
                                            block(thread)
        }
    }

    func sortIndex(thread: TSThread, transaction: YapDatabaseReadTransaction) -> UInt? {
        guard let view = ext(transaction) else {
            owsFailDebug("view was unexpectedly nil")
            return nil
        }

        var index: UInt = 0
        var group: NSString?
        let wasFound = view.getGroup(&group,
                                     index: &index,
                                     forKey: thread.uniqueId,
                                     inCollection: TSThread.collection())
        if wasFound, let group = group {
            let numberOfItems = view.numberOfItems(inGroup: group as String)
            guard numberOfItems > 0 else {
                owsFailDebug("numberOfItems <= 0")
                return nil
            }
            // since in yap our Inbox uses reversed sorting, our index must be reversed
            let reverseIndex = (Int(numberOfItems) - 1) - Int(index)
            guard reverseIndex >= 0 else {
                owsFailDebug("reverseIndex was < 0")
                return nil
            }
            return UInt(reverseIndex)
        } else {
            return nil
        }
    }

    // MARK: -

    private static let extensionName: String = TSThreadDatabaseViewExtensionName

    private func group(isArchived: Bool) -> String {
        return isArchived ? TSArchiveGroup : TSInboxGroup
    }

    private func ext(_ transaction: YapDatabaseReadTransaction) -> YapDatabaseViewTransaction? {
        return transaction.safeViewTransaction(type(of: self).extensionName)
    }
}

struct GRDBThreadFinder: ThreadFinder {

    typealias ReadTransaction = GRDBReadTransaction

    static let cn = ThreadRecord.columnName

    func visibleThreadCount(isArchived: Bool, transaction: GRDBReadTransaction) throws -> UInt {
        let sql = """
            SELECT COUNT(*)
            FROM \(ThreadRecord.databaseTableName)
            WHERE \(threadColumn: .shouldThreadBeVisible) = 1
            AND \(threadColumn: .isArchived) = ?
        """
        let arguments: StatementArguments = [isArchived]

        guard let count = try UInt.fetchOne(transaction.database, sql: sql, arguments: arguments) else {
            owsFailDebug("count was unexpectedly nil")
            return 0
        }

        return count
    }

    func enumerateVisibleThreads(isArchived: Bool, transaction: GRDBReadTransaction, block: @escaping (TSThread) -> Void) throws {
        let sql = """
            SELECT *
            FROM \(ThreadRecord.databaseTableName)
            WHERE \(threadColumn: .shouldThreadBeVisible) = 1
            AND \(threadColumn: .isArchived) = ?
            ORDER BY \(threadColumn: .lastInteractionRowId) DESC
            """
        let arguments: StatementArguments = [isArchived]

        try ThreadRecord.fetchCursor(transaction.database, sql: sql, arguments: arguments).forEach { threadRecord in
            block(try TSThread.fromRecord(threadRecord))
        }
    }

    func sortIndex(thread: TSThread, transaction: GRDBReadTransaction) throws -> UInt? {
        let sql = """
        SELECT sortIndex
        FROM (
            SELECT
                (ROW_NUMBER() OVER (ORDER BY \(threadColumn: .lastInteractionRowId) DESC) - 1) as sortIndex,
                \(threadColumn: .id)
            FROM \(ThreadRecord.databaseTableName)
            WHERE \(threadColumn: .shouldThreadBeVisible) = 1
        )
        WHERE \(threadColumn: .id) = ?
        """
        guard let grdbId = thread.grdbId, grdbId.intValue > 0 else {
            throw OWSAssertionError("grdbId was unexpectedly nil")
        }

        let arguments: StatementArguments = [grdbId.intValue]
        return try UInt.fetchOne(transaction.database, sql: sql, arguments: arguments)
    }
}
