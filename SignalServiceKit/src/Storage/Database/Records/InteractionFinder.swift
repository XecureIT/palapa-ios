//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import GRDB

protocol InteractionFinderAdapter {
    associatedtype ReadTransaction

    // MARK: - static methods

    static func fetch(uniqueId: String, transaction: ReadTransaction) throws -> TSInteraction?

    static func existsIncomingMessage(timestamp: UInt64, address: SignalServiceAddress, sourceDeviceId: UInt32, transaction: ReadTransaction) -> Bool

    static func interactions(withTimestamp timestamp: UInt64, filter: @escaping (TSInteraction) -> Bool, transaction: ReadTransaction) throws -> [TSInteraction]

    static func incompleteCallIds(transaction: ReadTransaction) -> [String]

    static func attemptingOutInteractionIds(transaction: ReadTransaction) -> [String]

    static func unreadCountInAllThreads(transaction: ReadTransaction) -> UInt

    // The interactions should be enumerated in order from "first to expire" to "last to expire".
    static func enumerateMessagesWithStartedPerConversationExpiration(transaction: ReadTransaction, block: @escaping (TSInteraction, UnsafeMutablePointer<ObjCBool>) -> Void)

    static func interactionIdsWithExpiredPerConversationExpiration(transaction: ReadTransaction) -> [String]

    static func enumerateMessagesWhichFailedToStartExpiring(transaction: ReadTransaction, block: @escaping (TSMessage, UnsafeMutablePointer<ObjCBool>) -> Void)

    // MARK: - instance methods

    func mostRecentInteractionForInbox(transaction: ReadTransaction) -> TSInteraction?

    func sortIndex(interactionUniqueId: String, transaction: ReadTransaction) throws -> UInt?
    func count(transaction: ReadTransaction) -> UInt
    func unreadCount(transaction: ReadTransaction) -> UInt
    func enumerateInteractionIds(transaction: ReadTransaction, block: @escaping (String, UnsafeMutablePointer<ObjCBool>) throws -> Void) throws
    func enumerateRecentInteractions(transaction: ReadTransaction, block: @escaping (TSInteraction, UnsafeMutablePointer<ObjCBool>) -> Void) throws
    func enumerateInteractions(range: NSRange, transaction: ReadTransaction, block: @escaping (TSInteraction, UnsafeMutablePointer<ObjCBool>) -> Void) throws
    func enumerateUnseenInteractions(transaction: ReadTransaction, block: @escaping (TSInteraction, UnsafeMutablePointer<ObjCBool>) -> Void) throws
    func oldestUnseenInteraction(transaction: ReadTransaction) throws -> TSInteraction?
    func existsOutgoingMessage(transaction: ReadTransaction) -> Bool
    func outgoingMessageCount(transaction: ReadTransaction) -> UInt

    func interaction(at index: UInt, transaction: ReadTransaction) throws -> TSInteraction?

    #if DEBUG
    func enumerateUnstartedExpiringMessages(transaction: ReadTransaction, block: @escaping (TSMessage, UnsafeMutablePointer<ObjCBool>) -> Void)
    #endif
}

// MARK: -

@objc
public class InteractionFinder: NSObject, InteractionFinderAdapter {

    let yapAdapter: YAPDBInteractionFinderAdapter
    let grdbAdapter: GRDBInteractionFinderAdapter

    @objc
    public init(threadUniqueId: String) {
        self.yapAdapter = YAPDBInteractionFinderAdapter(threadUniqueId: threadUniqueId)
        self.grdbAdapter = GRDBInteractionFinderAdapter(threadUniqueId: threadUniqueId)
    }

    // MARK: - static methods

    @objc
    public class func fetchSwallowingErrors(uniqueId: String, transaction: SDSAnyReadTransaction) -> TSInteraction? {
        do {
            return try fetch(uniqueId: uniqueId, transaction: transaction)
        } catch {
            owsFailDebug("error: \(error)")
            return nil
        }
    }

    public class func fetch(uniqueId: String, transaction: SDSAnyReadTransaction) throws -> TSInteraction? {
        switch transaction.readTransaction {
        case .yapRead(let yapRead):
            return YAPDBInteractionFinderAdapter.fetch(uniqueId: uniqueId, transaction: yapRead)
        case .grdbRead(let grdbRead):
            return try GRDBInteractionFinderAdapter.fetch(uniqueId: uniqueId, transaction: grdbRead)
        }
    }

    @objc
    public class func existsIncomingMessage(timestamp: UInt64, address: SignalServiceAddress, sourceDeviceId: UInt32, transaction: SDSAnyReadTransaction) -> Bool {
        switch transaction.readTransaction {
        case .yapRead(let yapRead):
            return YAPDBInteractionFinderAdapter.existsIncomingMessage(timestamp: timestamp, address: address, sourceDeviceId: sourceDeviceId, transaction: yapRead)
        case .grdbRead(let grdbRead):
            return GRDBInteractionFinderAdapter.existsIncomingMessage(timestamp: timestamp, address: address, sourceDeviceId: sourceDeviceId, transaction: grdbRead)
        }
    }

    @objc
    public class func interactions(withTimestamp timestamp: UInt64, filter: @escaping (TSInteraction) -> Bool, transaction: SDSAnyReadTransaction) throws -> [TSInteraction] {
        switch transaction.readTransaction {
        case .yapRead(let yapRead):
            return try YAPDBInteractionFinderAdapter.interactions(withTimestamp: timestamp,
                                                                  filter: filter,
                                                                  transaction: yapRead)
        case .grdbRead(let grdbRead):
            return try GRDBInteractionFinderAdapter.interactions(withTimestamp: timestamp,
                                                                 filter: filter,
                                                                 transaction: grdbRead)
        }
    }

    @objc
    public class func incompleteCallIds(transaction: SDSAnyReadTransaction) -> [String] {
        switch transaction.readTransaction {
        case .yapRead(let yapRead):
            return YAPDBInteractionFinderAdapter.incompleteCallIds(transaction: yapRead)
        case .grdbRead(let grdbRead):
            return GRDBInteractionFinderAdapter.incompleteCallIds(transaction: grdbRead)
        }
    }

    @objc
    public class func attemptingOutInteractionIds(transaction: SDSAnyReadTransaction) -> [String] {
        switch transaction.readTransaction {
        case .yapRead(let yapRead):
            return YAPDBInteractionFinderAdapter.attemptingOutInteractionIds(transaction: yapRead)
        case .grdbRead(let grdbRead):
            return GRDBInteractionFinderAdapter.attemptingOutInteractionIds(transaction: grdbRead)
        }
    }

    @objc
    public class func unreadCountInAllThreads(transaction: SDSAnyReadTransaction) -> UInt {
        switch transaction.readTransaction {
        case .yapRead(let yapRead):
            return YAPDBInteractionFinderAdapter.unreadCountInAllThreads(transaction: yapRead)
        case .grdbRead(let grdbRead):
            return GRDBInteractionFinderAdapter.unreadCountInAllThreads(transaction: grdbRead)
        }
    }

    // The interactions should be enumerated in order from "next to expire" to "last to expire".
    @objc
    public class func enumerateMessagesWithStartedPerConversationExpiration(transaction: SDSAnyReadTransaction, block: @escaping (TSInteraction, UnsafeMutablePointer<ObjCBool>) -> Void) {
        switch transaction.readTransaction {
        case .yapRead(let yapRead):
            YAPDBInteractionFinderAdapter.enumerateMessagesWithStartedPerConversationExpiration(transaction: yapRead, block: block)
        case .grdbRead(let grdbRead):
            GRDBInteractionFinderAdapter.enumerateMessagesWithStartedPerConversationExpiration(transaction: grdbRead, block: block)
        }
    }

    @objc
    public class func interactionIdsWithExpiredPerConversationExpiration(transaction: SDSAnyReadTransaction) -> [String] {
        switch transaction.readTransaction {
        case .yapRead(let yapRead):
            return YAPDBInteractionFinderAdapter.interactionIdsWithExpiredPerConversationExpiration(transaction: yapRead)
        case .grdbRead(let grdbRead):
            return GRDBInteractionFinderAdapter.interactionIdsWithExpiredPerConversationExpiration(transaction: grdbRead)
        }
    }

    @objc
    public class func enumerateMessagesWhichFailedToStartExpiring(transaction: SDSAnyReadTransaction, block: @escaping (TSMessage, UnsafeMutablePointer<ObjCBool>) -> Void) {
        switch transaction.readTransaction {
        case .yapRead(let yapRead):
            YAPDBInteractionFinderAdapter.enumerateMessagesWhichFailedToStartExpiring(transaction: yapRead, block: block)
        case .grdbRead(let grdbRead):
            GRDBInteractionFinderAdapter.enumerateMessagesWhichFailedToStartExpiring(transaction: grdbRead, block: block)
        }
    }

    @objc
    public class func findMessage(
        withTimestamp timestamp: UInt64,
        threadId: String,
        author: SignalServiceAddress,
        transaction: SDSAnyReadTransaction
    ) -> TSMessage? {
        guard timestamp > 0 else {
            owsFailDebug("invalid timestamp: \(timestamp)")
            return nil
        }

        guard !threadId.isEmpty else {
            owsFailDebug("invalid thread")
            return nil
        }

        guard author.isValid else {
            owsFailDebug("Invalid author \(author)")
            return nil
        }

        let interactions: [TSInteraction]

        do {
            interactions = try InteractionFinder.interactions(
                withTimestamp: timestamp,
                filter: { $0 is TSMessage },
                transaction: transaction
            )
        } catch {
            owsFailDebug("Error loading interactions \(error.localizedDescription)")
            return nil
        }

        for interaction in interactions {
            guard let message = interaction as? TSMessage else {
                owsFailDebug("received unexpected non-message interaction")
                continue
            }

            guard message.uniqueThreadId == threadId else { continue }

            if let incomingMessage = message as? TSIncomingMessage,
                incomingMessage.authorAddress.isEqualToAddress(author) {
                return incomingMessage
            }

            if let outgoingMessage = message as? TSOutgoingMessage,
                author.isLocalAddress {
                return outgoingMessage
            }
        }

        return nil
    }

    // MARK: - instance methods

    @objc
    func mostRecentInteractionForInbox(transaction: SDSAnyReadTransaction) -> TSInteraction? {
        switch transaction.readTransaction {
        case .yapRead(let yapRead):
            return yapAdapter.mostRecentInteractionForInbox(transaction: yapRead)
        case .grdbRead(let grdbRead):
            return grdbAdapter.mostRecentInteractionForInbox(transaction: grdbRead)
        }
    }

    public func sortIndex(interactionUniqueId: String, transaction: SDSAnyReadTransaction) throws -> UInt? {
        return try Bench(title: "sortIndex") {
            switch transaction.readTransaction {
            case .yapRead(let yapRead):
                return yapAdapter.sortIndex(interactionUniqueId: interactionUniqueId, transaction: yapRead)
            case .grdbRead(let grdbRead):
                return try grdbAdapter.sortIndex(interactionUniqueId: interactionUniqueId, transaction: grdbRead)
            }
        }
    }

    @objc
    public func count(transaction: SDSAnyReadTransaction) -> UInt {
        switch transaction.readTransaction {
        case .yapRead(let yapRead):
            return yapAdapter.count(transaction: yapRead)
        case .grdbRead(let grdbRead):
            return grdbAdapter.count(transaction: grdbRead)
        }
    }

    @objc
    public func unreadCount(transaction: SDSAnyReadTransaction) -> UInt {
        switch transaction.readTransaction {
        case .yapRead(let yapRead):
            return yapAdapter.unreadCount(transaction: yapRead)
        case .grdbRead(let grdbRead):
            return grdbAdapter.unreadCount(transaction: grdbRead)
        }
    }

    public func enumerateInteractionIds(transaction: SDSAnyReadTransaction, block: @escaping (String, UnsafeMutablePointer<ObjCBool>) throws -> Void) throws {
        switch transaction.readTransaction {
        case .yapRead(let yapRead):
            return try yapAdapter.enumerateInteractionIds(transaction: yapRead, block: block)
        case .grdbRead(let grdbRead):
            return try grdbAdapter.enumerateInteractionIds(transaction: grdbRead, block: block)
        }
    }

    @objc
    public func enumerateInteractionIds(transaction: SDSAnyReadTransaction, block: @escaping (String, UnsafeMutablePointer<ObjCBool>) -> Void) throws {
        switch transaction.readTransaction {
        case .yapRead(let yapRead):
            return try yapAdapter.enumerateInteractionIds(transaction: yapRead, block: block)
        case .grdbRead(let grdbRead):
            return try grdbAdapter.enumerateInteractionIds(transaction: grdbRead, block: block)
        }
    }

    @objc
    public func enumerateRecentInteractions(transaction: SDSAnyReadTransaction, block: @escaping (TSInteraction, UnsafeMutablePointer<ObjCBool>) -> Void) throws {
        switch transaction.readTransaction {
        case .yapRead(let yapRead):
            return try yapAdapter.enumerateRecentInteractions(transaction: yapRead, block: block)
        case .grdbRead(let grdbRead):
            return try grdbAdapter.enumerateRecentInteractions(transaction: grdbRead, block: block)
        }
    }

    public func enumerateInteractions(range: NSRange, transaction: SDSAnyReadTransaction, block: @escaping (TSInteraction, UnsafeMutablePointer<ObjCBool>) -> Void) throws {
        switch transaction.readTransaction {
        case .yapRead(let yapRead):
            return yapAdapter.enumerateInteractions(range: range, transaction: yapRead, block: block)
        case .grdbRead(let grdbRead):
            return try grdbAdapter.enumerateInteractions(range: range, transaction: grdbRead, block: block)
        }
    }

    @objc
    public func enumerateUnseenInteractions(transaction: SDSAnyReadTransaction, block: @escaping (TSInteraction, UnsafeMutablePointer<ObjCBool>) -> Void) throws {
        switch transaction.readTransaction {
        case .yapRead(let yapRead):
            return try yapAdapter.enumerateUnseenInteractions(transaction: yapRead, block: block)
        case .grdbRead(let grdbRead):
            return try grdbAdapter.enumerateUnseenInteractions(transaction: grdbRead, block: block)
        }
    }

    public func oldestUnseenInteraction(transaction: SDSAnyReadTransaction) throws -> TSInteraction? {
        switch transaction.readTransaction {
        case .yapRead(let yapRead):
            return try yapAdapter.oldestUnseenInteraction(transaction: yapRead)
        case .grdbRead(let grdbRead):
            return try grdbAdapter.oldestUnseenInteraction(transaction: grdbRead)
        }
    }

    public func interaction(at index: UInt, transaction: SDSAnyReadTransaction) throws -> TSInteraction? {
        switch transaction.readTransaction {
        case .yapRead(let yapRead):
            return yapAdapter.interaction(at: index, transaction: yapRead)
        case .grdbRead(let grdbRead):
            return try grdbAdapter.interaction(at: index, transaction: grdbRead)
        }
    }

    @objc
    public func existsOutgoingMessage(transaction: SDSAnyReadTransaction) -> Bool {
        switch transaction.readTransaction {
        case .yapRead(let yapRead):
            return yapAdapter.existsOutgoingMessage(transaction: yapRead)
        case .grdbRead(let grdbRead):
            return grdbAdapter.existsOutgoingMessage(transaction: grdbRead)
        }
    }

    #if DEBUG
    @objc
    public func enumerateUnstartedExpiringMessages(transaction: SDSAnyReadTransaction, block: @escaping (TSMessage, UnsafeMutablePointer<ObjCBool>) -> Void) {
        switch transaction.readTransaction {
        case .yapRead(let yapRead):
            return yapAdapter.enumerateUnstartedExpiringMessages(transaction: yapRead, block: block)
        case .grdbRead(let grdbRead):
            return grdbAdapter.enumerateUnstartedExpiringMessages(transaction: grdbRead, block: block)
        }
    }
    #endif

    @objc
    public func outgoingMessageCount(transaction: SDSAnyReadTransaction) -> UInt {
        switch transaction.readTransaction {
        case .yapRead(let yapRead):
            return yapAdapter.outgoingMessageCount(transaction: yapRead)
        case .grdbRead(let grdbRead):
            return grdbAdapter.outgoingMessageCount(transaction: grdbRead)
        }
    }
}

// MARK: -

// GRDB TODO: Nice to have: pull all of the YDB finder logic into this file.
struct YAPDBInteractionFinderAdapter: InteractionFinderAdapter {

    private let threadUniqueId: String

    init(threadUniqueId: String) {
        self.threadUniqueId = threadUniqueId
    }

    // MARK: - static methods

    static func fetch(uniqueId: String, transaction: YapDatabaseReadTransaction) -> TSInteraction? {
        return transaction.object(forKey: uniqueId, inCollection: TSInteraction.collection()) as? TSInteraction
    }

    static func existsIncomingMessage(timestamp: UInt64, address: SignalServiceAddress, sourceDeviceId: UInt32, transaction: YapDatabaseReadTransaction) -> Bool {
        return OWSIncomingMessageFinder().existsMessage(withTimestamp: timestamp, address: address, sourceDeviceId: sourceDeviceId, transaction: transaction)
    }

    static func incompleteCallIds(transaction: YapDatabaseReadTransaction) -> [String] {
        return OWSIncompleteCallsJob.ydb_incompleteCallIds(with: transaction)
    }

    static func attemptingOutInteractionIds(transaction: YapDatabaseReadTransaction) -> [String] {
        return OWSFailedMessagesJob.attemptingOutMessageIds(with: transaction)
    }

    static func unreadCountInAllThreads(transaction: YapDatabaseReadTransaction) -> UInt {
        guard let view = unreadExt(transaction) else {
            return 0
        }
        return view.numberOfItemsInAllGroups()
    }

    static func interactions(withTimestamp timestamp: UInt64, filter: @escaping (TSInteraction) -> Bool, transaction: YapDatabaseReadTransaction) throws -> [TSInteraction] {
        return TSInteraction.ydb_interactions(withTimestamp: timestamp,
                                              filter: filter,
                                              with: transaction)
    }

    // The interactions should be enumerated in order from "next to expire" to "last to expire".
    static func enumerateMessagesWithStartedPerConversationExpiration(transaction: YapDatabaseReadTransaction, block: @escaping (TSInteraction, UnsafeMutablePointer<ObjCBool>) -> Void) {
        OWSDisappearingMessagesFinder.ydb_enumerateMessagesWithStartedPerConversationExpiration(block, transaction: transaction)
    }

    static func interactionIdsWithExpiredPerConversationExpiration(transaction: ReadTransaction) -> [String] {
        return OWSDisappearingMessagesFinder.ydb_interactionIdsWithExpiredPerConversationExpiration(with: transaction)
    }

    static func enumerateMessagesWhichFailedToStartExpiring(transaction: YapDatabaseReadTransaction, block: @escaping (TSMessage, UnsafeMutablePointer<ObjCBool>) -> Void) {
        OWSDisappearingMessagesFinder.ydb_enumerateMessagesWhichFailedToStartExpiring(block, transaction: transaction)
    }

    // MARK: - instance methods

    func mostRecentInteractionForInbox(transaction: YapDatabaseReadTransaction) -> TSInteraction? {
        var last: TSInteraction?
        var missedCount: UInt = 0
        guard let view = interactionExt(transaction) else {
            return nil
        }
        view.safe_enumerateKeysAndObjects(inGroup: threadUniqueId,
                                          extensionName: TSMessageDatabaseViewExtensionName,
                                          with: NSEnumerationOptions.reverse) { (_, _, object, _, stopPtr) in
            guard let interaction = object as? TSInteraction else {
                owsFailDebug("unexpected interaction: \(type(of: object))")
                return
            }
            if TSThread.shouldInteractionAppear(inInbox: interaction) {
                last = interaction
                stopPtr.pointee = true
            }

            missedCount += 1
            // For long ignored threads, with lots of SN changes this can get really slow.
            // I see this in development because I have a lot of long forgotten threads with
            // members who's test devices are constantly reinstalled. We could add a
            // purpose-built DB view, but I think in the real world this is rare to be a
            // hotspot.
            if (missedCount > 50) {
                Logger.warn("found last interaction for inbox after skipping \(missedCount) items")
            }
        }
        return last
    }

    func count(transaction: YapDatabaseReadTransaction) -> UInt {
        guard let view = interactionExt(transaction) else {
            return 0
        }
        return view.numberOfItems(inGroup: threadUniqueId)
    }

    func unreadCount(transaction: YapDatabaseReadTransaction) -> UInt {
        guard let view = unreadExt(transaction) else {
            return 0
        }
        return view.numberOfItems(inGroup: threadUniqueId)
    }

    func sortIndex(interactionUniqueId: String, transaction: YapDatabaseReadTransaction) -> UInt? {
        var index: UInt = 0
        guard let view = interactionExt(transaction) else {
            return nil
        }
        let wasFound = view.getGroup(nil, index: &index, forKey: interactionUniqueId, inCollection: collection)

        guard wasFound else {
            return nil
        }

        return index
    }

    func enumerateInteractionIds(transaction: YapDatabaseReadTransaction, block: @escaping (String, UnsafeMutablePointer<ObjCBool>) throws -> Void) throws {
        var errorToRaise: Error?
        guard let view = interactionExt(transaction) else {
            return
        }
        view.enumerateKeys(inGroup: threadUniqueId, with: NSEnumerationOptions.reverse) { (_, key, _, stopPtr) in
            do {
                try block(key, stopPtr)
            } catch {
                // the block parameter is a `throws` block because the GRDB implementation can throw
                // we don't expect this with YapDB, though we still try to handle it.
                owsFailDebug("unexpected error: \(error)")
                stopPtr.pointee = true
                errorToRaise = error
            }
        }
        if let errorToRaise = errorToRaise {
            throw errorToRaise
        }
    }

    func enumerateRecentInteractions(transaction: YapDatabaseReadTransaction, block: @escaping (TSInteraction, UnsafeMutablePointer<ObjCBool>) -> Void) throws {
        guard let view = interactionExt(transaction) else {
            return
        }
        view.safe_enumerateKeysAndObjects(inGroup: threadUniqueId,
                                          extensionName: TSMessageDatabaseViewExtensionName,
                                          with: NSEnumerationOptions.reverse) { (_, _, object, _, stopPtr) in
                                            guard let interaction = object as? TSInteraction else {
                                                owsFailDebug("unexpected interaction: \(type(of: object))")
                                                return
                                            }
                                            block(interaction, stopPtr)
        }
    }

    func enumerateInteractions(range: NSRange, transaction: YapDatabaseReadTransaction, block: @escaping (TSInteraction, UnsafeMutablePointer<ObjCBool>) -> Void) {
        guard let view = interactionExt(transaction) else {
            return
        }
        view.enumerateKeysAndObjects(inGroup: threadUniqueId, with: [], range: range) { (_, _, object, _, stopPtr) in
            guard let interaction = object as? TSInteraction else {
                owsFailDebug("unexpected object: \(type(of: object))")
                return
            }

            block(interaction, stopPtr)
        }
    }

    func enumerateUnseenInteractions(transaction: YapDatabaseReadTransaction, block: @escaping (TSInteraction, UnsafeMutablePointer<ObjCBool>) -> Void) throws {
        guard let view = unseenExt(transaction) else {
            return
        }
        // `isOrdered` is unused for yap. Views are always ordered.
        view.safe_enumerateKeysAndObjects(inGroup: threadUniqueId,
                                          extensionName: TSUnseenDatabaseViewExtensionName,
                                          with: []) { (_, _, object, _, stopPtr) in
                                            guard let interaction = object as? TSInteraction else {
                                                owsFailDebug("unexpected interaction: \(type(of: object))")
                                                return
                                            }
            block(interaction, stopPtr)
        }
    }

    func oldestUnseenInteraction(transaction: YapDatabaseReadTransaction) throws -> TSInteraction? {
        guard let view = unseenExt(transaction) else {
            return nil
        }
        var result: TSInteraction?
        view.safe_enumerateKeysAndObjects(inGroup: threadUniqueId,
                                          extensionName: TSUnseenDatabaseViewExtensionName,
                                          with: []) { (_, _, object, _, stopPtr) in
                                            guard let interaction = object as? TSInteraction else {
                                                owsFailDebug("unexpected interaction: \(type(of: object))")
                                                return
                                            }
                                            result = interaction
                                            stopPtr.pointee = true
        }
        return result
    }

    func interaction(at index: UInt, transaction: YapDatabaseReadTransaction) -> TSInteraction? {
        guard let view = interactionExt(transaction) else {
            return nil
        }
        guard let obj = view.object(at: index, inGroup: threadUniqueId) else {
            return nil
        }

        guard let interaction = obj as? TSInteraction else {
            owsFailDebug("unexpected interaction: \(type(of: obj))")
            return nil
        }

        return interaction
    }

    func existsOutgoingMessage(transaction: YapDatabaseReadTransaction) -> Bool {
        guard let dbView = TSDatabaseView.threadOutgoingMessageDatabaseView(transaction) as? YapDatabaseAutoViewTransaction else {
            owsFailDebug("unexpected view")
            return false
        }
        return !dbView.isEmptyGroup(threadUniqueId)
    }

    #if DEBUG
    func enumerateUnstartedExpiringMessages(transaction: YapDatabaseReadTransaction, block: @escaping (TSMessage, UnsafeMutablePointer<ObjCBool>) -> Void) {
        OWSDisappearingMessagesFinder.ydb_enumerateUnstartedExpiringMessages(withThreadId: self.threadUniqueId,
                                                                             block: block,
                                                                             transaction: transaction)
    }
    #endif

    func outgoingMessageCount(transaction: YapDatabaseReadTransaction) -> UInt {
        guard let dbView = TSDatabaseView.threadOutgoingMessageDatabaseView(transaction) as? YapDatabaseAutoViewTransaction else {
            owsFailDebug("unexpected view")
            return 0
        }
        return dbView.numberOfItems(inGroup: threadUniqueId)
    }

    // MARK: - private

    private var collection: String {
        return TSInteraction.collection()
    }

    private static func unreadExt(_ transaction: YapDatabaseReadTransaction) -> YapDatabaseViewTransaction? {
        return transaction.safeViewTransaction(TSUnreadDatabaseViewExtensionName)
    }

    private func unreadExt(_ transaction: YapDatabaseReadTransaction) -> YapDatabaseViewTransaction? {
        return YAPDBInteractionFinderAdapter.unreadExt(transaction)
    }

    private func interactionExt(_ transaction: YapDatabaseReadTransaction) -> YapDatabaseViewTransaction? {
        return transaction.safeViewTransaction(TSMessageDatabaseViewExtensionName)
    }

    private func unseenExt(_ transaction: YapDatabaseReadTransaction) -> YapDatabaseViewTransaction? {
        return transaction.safeViewTransaction(TSUnseenDatabaseViewExtensionName)
    }
}

// MARK: -

struct GRDBInteractionFinderAdapter: InteractionFinderAdapter {

    typealias ReadTransaction = GRDBReadTransaction

    let threadUniqueId: String

    init(threadUniqueId: String) {
        self.threadUniqueId = threadUniqueId
    }

    // MARK: - static methods

    static func fetch(uniqueId: String, transaction: GRDBReadTransaction) throws -> TSInteraction? {
        return TSInteraction.anyFetch(uniqueId: uniqueId, transaction: transaction.asAnyRead)
    }

    static func existsIncomingMessage(timestamp: UInt64, address: SignalServiceAddress, sourceDeviceId: UInt32, transaction: GRDBReadTransaction) -> Bool {
        var exists = false
        if let uuidString = address.uuidString {
            let sql = """
                SELECT EXISTS(
                    SELECT 1
                    FROM \(InteractionRecord.databaseTableName)
                    WHERE \(interactionColumn: .timestamp) = ?
                    AND \(interactionColumn: .authorUUID) = ?
                    AND \(interactionColumn: .sourceDeviceId) = ?
                )
            """
            let arguments: StatementArguments = [timestamp, uuidString, sourceDeviceId]
            exists = try! Bool.fetchOne(transaction.database, sql: sql, arguments: arguments) ?? false
        }

        if !exists, let phoneNumber = address.phoneNumber {
            let sql = """
                SELECT EXISTS(
                    SELECT 1
                    FROM \(InteractionRecord.databaseTableName)
                    WHERE \(interactionColumn: .timestamp) = ?
                    AND \(interactionColumn: .authorPhoneNumber) = ?
                    AND \(interactionColumn: .sourceDeviceId) = ?
                )
            """
            let arguments: StatementArguments = [timestamp, phoneNumber, sourceDeviceId]
            exists = try! Bool.fetchOne(transaction.database, sql: sql, arguments: arguments) ?? false
        }

        return exists
    }

    static func interactions(withTimestamp timestamp: UInt64, filter: @escaping (TSInteraction) -> Bool, transaction: ReadTransaction) throws -> [TSInteraction] {
        let sql = """
        SELECT *
        FROM \(InteractionRecord.databaseTableName)
        WHERE \(interactionColumn: .timestamp) = ?
        """
        let arguments: StatementArguments = [timestamp]

        let unfiltered = try TSInteraction.grdbFetchCursor(sql: sql, arguments: arguments, transaction: transaction).all()
        return unfiltered.filter(filter)
    }

    static func incompleteCallIds(transaction: ReadTransaction) -> [String] {
        let sql: String = """
        SELECT \(interactionColumn: .uniqueId)
        FROM \(InteractionRecord.databaseTableName)
        WHERE \(interactionColumn: .recordType) = ?
        AND (
        \(interactionColumn: .callType) = ?
        OR \(interactionColumn: .callType) = ?
        )
        """
        let statementArguments: StatementArguments = [
            SDSRecordType.call.rawValue,
            RPRecentCallType.outgoingIncomplete.rawValue,
            RPRecentCallType.incomingIncomplete.rawValue
        ]
        var result = [String]()
        do {
            result = try String.fetchAll(transaction.database,
                                         sql: sql,
                                         arguments: statementArguments)
        } catch {
            owsFailDebug("error: \(error)")
        }
        return result
    }

    static func attemptingOutInteractionIds(transaction: ReadTransaction) -> [String] {
        let sql: String = """
        SELECT \(interactionColumn: .uniqueId)
        FROM \(InteractionRecord.databaseTableName)
        WHERE \(interactionColumn: .storedMessageState) = ?
        """
        var result = [String]()
        do {
            result = try String.fetchAll(transaction.database,
                                         sql: sql,
                                         arguments: [TSOutgoingMessageState.sending.rawValue])
        } catch {
            owsFailDebug("error: \(error)")
        }
        return result
    }

    static func unreadCountInAllThreads(transaction: ReadTransaction) -> UInt {
        do {
            let sql = """
                SELECT COUNT(*)
                FROM \(InteractionRecord.databaseTableName)
                WHERE \(sqlClauseForUnreadInteractionCounts)
            """
            guard let count = try UInt.fetchOne(transaction.database, sql: sql) else {
                owsFailDebug("count was unexpectedly nil")
                return 0
            }
            return count
        } catch {
            owsFailDebug("error: \(error)")
            return 0
        }
    }

    // The interactions should be enumerated in order from "next to expire" to "last to expire".
    static func enumerateMessagesWithStartedPerConversationExpiration(transaction: ReadTransaction, block: @escaping (TSInteraction, UnsafeMutablePointer<ObjCBool>) -> Void) {
        // NOTE: We DO NOT consult storedShouldStartExpireTimer here;
        //       once expiration has begun we want to see it through.
        let sql = """
        SELECT *
        FROM \(InteractionRecord.databaseTableName)
        WHERE \(interactionColumn: .expiresInSeconds) > 0
        AND \(interactionColumn: .expiresAt) > 0
        ORDER BY \(interactionColumn: .expiresAt)
        """
        let cursor = TSInteraction.grdbFetchCursor(sql: sql, transaction: transaction)
        do {
            while let interaction = try cursor.next() {
                var stop: ObjCBool = false
                block(interaction, &stop)
                if stop.boolValue {
                    return
                }
            }
        } catch {
            owsFail("error: \(error)")
        }
    }

    static func interactionIdsWithExpiredPerConversationExpiration(transaction: ReadTransaction) -> [String] {
        // NOTE: We DO NOT consult storedShouldStartExpireTimer here;
        //       once expiration has begun we want to see it through.
        let now: UInt64 = NSDate.ows_millisecondTimeStamp()
        let sql = """
        SELECT \(interactionColumn: .uniqueId)
        FROM \(InteractionRecord.databaseTableName)
        WHERE \(interactionColumn: .expiresAt) > 0
        AND \(interactionColumn: .expiresAt) <= ?
        """
        let statementArguments: StatementArguments = [
            now
        ]
        var result = [String]()
        do {
            result = try String.fetchAll(transaction.database,
                                         sql: sql,
                                         arguments: statementArguments)
        } catch {
            owsFailDebug("error: \(error)")
        }
        return result
    }

    static func enumerateMessagesWhichFailedToStartExpiring(transaction: ReadTransaction, block: @escaping (TSMessage, UnsafeMutablePointer<ObjCBool>) -> Void) {
        // NOTE: We DO consult storedShouldStartExpireTimer here.
        //       We don't want to start expiration until it is true.
        let sql = """
        SELECT *
        FROM \(InteractionRecord.databaseTableName)
        WHERE \(interactionColumn: .storedShouldStartExpireTimer) IS TRUE
        AND (
            \(interactionColumn: .expiresAt) IS 0 OR
            \(interactionColumn: .expireStartedAt) IS 0
        )
        """
        let cursor = TSInteraction.grdbFetchCursor(sql: sql, arguments: [], transaction: transaction)
        do {
            while let interaction = try cursor.next() {
                guard let message = interaction as? TSMessage else {
                    owsFailDebug("Unexpected object: \(type(of: interaction))")
                    return
                }
                var stop: ObjCBool = false
                block(message, &stop)
                if stop.boolValue {
                    return
                }
            }
        } catch {
            owsFail("error: \(error)")
        }
    }

    // MARK: - instance methods

    func mostRecentInteractionForInbox(transaction: GRDBReadTransaction) -> TSInteraction? {
        let sql = """
                SELECT *
                FROM \(InteractionRecord.databaseTableName)
                WHERE \(interactionColumn: .threadUniqueId) = ?
                AND \(interactionColumn: .errorType) IS NOT ?
                AND \(interactionColumn: .messageType) IS NOT ?
                ORDER BY \(interactionColumn: .id) DESC
                LIMIT 1
                """
        let arguments: StatementArguments = [threadUniqueId,
                                             TSErrorMessageType.nonBlockingIdentityChange.rawValue,
                                             TSInfoMessageType.verificationStateChange.rawValue]
        return TSInteraction.grdbFetchOne(sql: sql, arguments: arguments, transaction: transaction)
    }

    func sortIndex(interactionUniqueId: String, transaction: GRDBReadTransaction) throws -> UInt? {
        return try UInt.fetchOne(transaction.database,
                                 sql: """
            SELECT sortIndex
            FROM (
                SELECT
                    ROW_NUMBER() OVER (ORDER BY \(interactionColumn: .id)) - 1 as sortIndex,
                    \(interactionColumn: .id),
                    \(interactionColumn: .uniqueId)
                FROM \(InteractionRecord.databaseTableName)
                WHERE \(interactionColumn: .threadUniqueId) = ?
            )
            WHERE \(interactionColumn: .uniqueId) = ?
            """,
            arguments: [threadUniqueId, interactionUniqueId])
    }

    func count(transaction: GRDBReadTransaction) -> UInt {
        do {
            guard let count = try UInt.fetchOne(transaction.database,
                                                sql: """
                SELECT COUNT(*)
                FROM \(InteractionRecord.databaseTableName)
                WHERE \(interactionColumn: .threadUniqueId) = ?
                """,
                arguments: [threadUniqueId]) else {
                    throw assertionError("count was unexpectedly nil")
            }
            return count
        } catch {
            owsFail("error: \(error)")
        }
    }

    func unreadCount(transaction: GRDBReadTransaction) -> UInt {
        do {
            let sql = """
                SELECT COUNT(*)
                FROM \(InteractionRecord.databaseTableName)
                WHERE \(interactionColumn: .threadUniqueId) = ?
                AND \(GRDBInteractionFinderAdapter.sqlClauseForUnreadInteractionCounts)
            """
            let arguments: StatementArguments = [threadUniqueId]

            guard let count = try UInt.fetchOne(transaction.database,
                                                sql: sql,
                                                arguments: arguments) else {
                    owsFailDebug("count was unexpectedly nil")
                    return 0
            }
            return count
        } catch {
            owsFailDebug("error: \(error)")
            return 0
        }
    }

    func enumerateInteractionIds(transaction: GRDBReadTransaction, block: @escaping (String, UnsafeMutablePointer<ObjCBool>) throws -> Void) throws {

        let cursor = try String.fetchCursor(transaction.database,
                                            sql: """
            SELECT \(interactionColumn: .uniqueId)
            FROM \(InteractionRecord.databaseTableName)
            WHERE \(interactionColumn: .threadUniqueId) = ?
            ORDER BY \(interactionColumn: .id) DESC
            """,
            arguments: [threadUniqueId])
        while let uniqueId = try cursor.next() {
            var stop: ObjCBool = false
            try block(uniqueId, &stop)
            if stop.boolValue {
                return
            }
        }
    }

    func enumerateRecentInteractions(transaction: GRDBReadTransaction, block: @escaping (TSInteraction, UnsafeMutablePointer<ObjCBool>) -> Void) throws {
        let sql = """
        SELECT *
        FROM \(InteractionRecord.databaseTableName)
        WHERE \(interactionColumn: .threadUniqueId) = ?
        ORDER BY \(interactionColumn: .id) DESC
        """
        let arguments: StatementArguments = [threadUniqueId]
        let cursor = TSInteraction.grdbFetchCursor(sql: sql,
                                                   arguments: arguments,
                                                   transaction: transaction)

        while let interaction = try cursor.next() {
            var stop: ObjCBool = false
            block(interaction, &stop)
            if stop.boolValue {
                return
            }
        }
    }

    func enumerateInteractions(range: NSRange, transaction: GRDBReadTransaction, block: @escaping (TSInteraction, UnsafeMutablePointer<ObjCBool>) -> Void) throws {
        let sql = """
        SELECT *
        FROM \(InteractionRecord.databaseTableName)
        WHERE \(interactionColumn: .threadUniqueId) = ?
        ORDER BY \(interactionColumn: .id)
        LIMIT \(range.length)
        OFFSET \(range.location)
        """
        let arguments: StatementArguments = [threadUniqueId]
        let cursor = TSInteraction.grdbFetchCursor(sql: sql,
                                                   arguments: arguments,
                                                   transaction: transaction)

        while let interaction = try cursor.next() {
            var stop: ObjCBool = false
            block(interaction, &stop)
            if stop.boolValue {
                return
            }
        }
    }

    func enumerateUnseenInteractions(transaction: GRDBReadTransaction, block: @escaping (TSInteraction, UnsafeMutablePointer<ObjCBool>) -> Void) throws {

        let sql = """
            SELECT *
            FROM \(InteractionRecord.databaseTableName)
            WHERE \(interactionColumn: .threadUniqueId) = ?
            AND \(sqlClauseForAllUnreadInteractions)
        """
        let arguments: StatementArguments = [threadUniqueId]
        let cursor = TSInteraction.grdbFetchCursor(sql: sql, arguments: arguments, transaction: transaction)
        while let interaction = try cursor.next() {
            var stop: ObjCBool = false
            if interaction as? OWSReadTracking == nil {
                owsFailDebug("Interaction has unexpected type: \(type(of: interaction))")
            }
            block(interaction, &stop)
            if stop.boolValue {
                return
            }
        }
    }

    func oldestUnseenInteraction(transaction: GRDBReadTransaction) throws -> TSInteraction? {
        let sql = """
        SELECT *
        FROM \(InteractionRecord.databaseTableName)
        WHERE \(interactionColumn: .threadUniqueId) = ?
        AND \(sqlClauseForAllUnreadInteractions)
        ORDER BY \(interactionColumn: .id)
        """
        let cursor = TSInteraction.grdbFetchCursor(sql: sql, arguments: [threadUniqueId], transaction: transaction)
        return try cursor.next()
    }

    func interaction(at index: UInt, transaction: GRDBReadTransaction) throws -> TSInteraction? {
        let sql = """
        SELECT *
        FROM \(InteractionRecord.databaseTableName)
        WHERE \(interactionColumn: .threadUniqueId) = ?
        ORDER BY \(interactionColumn: .id) DESC
        LIMIT 1
        OFFSET ?
        """
        let arguments: StatementArguments = [threadUniqueId, index]
        return TSInteraction.grdbFetchOne(sql: sql, arguments: arguments, transaction: transaction)
    }

    func existsOutgoingMessage(transaction: GRDBReadTransaction) -> Bool {
        let sql = """
        SELECT EXISTS(
            SELECT 1
            FROM \(InteractionRecord.databaseTableName)
            WHERE \(interactionColumn: .threadUniqueId) = ?
            AND \(interactionColumn: .recordType) = ?
            LIMIT 1
        )
        """
        let arguments: StatementArguments = [threadUniqueId, SDSRecordType.outgoingMessage.rawValue]
        return try! Bool.fetchOne(transaction.database, sql: sql, arguments: arguments) ?? false
    }

    #if DEBUG
    func enumerateUnstartedExpiringMessages(transaction: GRDBReadTransaction, block: @escaping (TSMessage, UnsafeMutablePointer<ObjCBool>) -> Void) {
        // NOTE: We DO consult storedShouldStartExpireTimer here.
        //       We don't want to start expiration until it is true.
        let sql = """
        SELECT *
        FROM \(InteractionRecord.databaseTableName)
        WHERE \(interactionColumn: .threadUniqueId) = ?
        AND \(interactionColumn: .storedShouldStartExpireTimer) IS TRUE
        AND (
            \(interactionColumn: .expiresAt) IS 0 OR
            \(interactionColumn: .expireStartedAt) IS 0
        )
        """
        let cursor = TSInteraction.grdbFetchCursor(sql: sql, arguments: [threadUniqueId], transaction: transaction)
        do {
            while let interaction = try cursor.next() {
                guard let message = interaction as? TSMessage else {
                    owsFailDebug("Unexpected object: \(type(of: interaction))")
                    return
                }
                var stop: ObjCBool = false
                block(message, &stop)
                if stop.boolValue {
                    return
                }
            }
        } catch {
            owsFail("error: \(error)")
        }
    }
    #endif

    func outgoingMessageCount(transaction: GRDBReadTransaction) -> UInt {
        let sql = """
        SELECT COUNT(*)
        FROM \(InteractionRecord.databaseTableName)
        WHERE \(interactionColumn: .threadUniqueId) = ?
        AND \(interactionColumn: .recordType) = ?
        """
        let arguments: StatementArguments = [threadUniqueId, SDSRecordType.outgoingMessage.rawValue]
        return try! UInt.fetchOne(transaction.database, sql: sql, arguments: arguments) ?? 0
    }

    // MARK: - Unseen & Unread

    private let sqlClauseForAllUnreadInteractions: String = {
        // The nomenclature we've inherited from our YDB database views is confusing.
        //
        // * "Unseen" refers to "all unread interactions".
        // * "Unread" refers to "unread interactions which affect unread counts".
        //
        // This clause is used for the former case.
        //
        // We can either whitelist or blacklist interactions.
        // It's a lot easier to whitelist.
        //
        // POST GRDB TODO: Rename "unseen" and "unread" finder methods.
        let recordTypes: [SDSRecordType] = [
            .disappearingConfigurationUpdateInfoMessage,
            .unknownProtocolVersionMessage,
            .verificationStateChangeMessage,
            .call,
            .errorMessage,
            .incomingMessage,
            .infoMessage,
            .invalidIdentityKeyErrorMessage,
            .invalidIdentityKeyReceivingErrorMessage,
            .invalidIdentityKeySendingErrorMessage
        ]

        let recordTypesSql = recordTypes.map { "\($0.rawValue)" }.joined(separator: ",")

        return """
        (
            \(interactionColumn: .read) IS 0
            AND \(interactionColumn: .recordType) IN (\(recordTypesSql))
        )
        """
    }()

    private static let sqlClauseForUnreadInteractionCounts: String = {
        // The nomenclature we've inherited from our YDB database views is confusing.
        //
        // * "Unseen" refers to "all unread interactions".
        // * "Unread" refers to "unread interactions which affect unread counts".
        //
        // This clause is used for the latter case.
        //
        // We can either whitelist or blacklist interactions.
        // It's a lot easier to whitelist.
        //
        // POST GRDB TODO: Rename "unseen" and "unread" finder methods.
        return """
        \(interactionColumn: .read) IS 0
        AND (
            \(interactionColumn: .recordType) IN (\(SDSRecordType.incomingMessage.rawValue), \(SDSRecordType.call.rawValue))
            OR (
                \(interactionColumn: .recordType) IS \(SDSRecordType.infoMessage.rawValue)
                AND \(interactionColumn: .messageType) IS \(TSInfoMessageType.userJoinedSignal.rawValue)
            )
        )
        """
    }()
}

private func assertionError(_ description: String) -> Error {
    return OWSErrorMakeAssertionError(description)
}
