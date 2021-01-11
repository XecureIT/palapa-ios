//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit

public typealias MessageSortKey = UInt64
public struct ConversationSortKey: Comparable {
    let isContactThread: Bool
    let creationDate: Date?
    let lastInteractionRowId: Int64

    // MARK: Comparable

    public static func < (lhs: ConversationSortKey, rhs: ConversationSortKey) -> Bool {
        // always show matching contact results first
        if lhs.isContactThread, !rhs.isContactThread {
            return false
        } else if !lhs.isContactThread, rhs.isContactThread {
            return true
        }

        if lhs.lastInteractionRowId != rhs.lastInteractionRowId {
            return lhs.lastInteractionRowId < rhs.lastInteractionRowId
        }
        let longAgo = Date(timeIntervalSince1970: 0)
        let lhsDate = lhs.creationDate ?? longAgo
        let rhsDate = rhs.creationDate ?? longAgo
        return lhsDate < rhsDate
    }
}

public class ConversationSearchResult<SortKey>: Comparable where SortKey: Comparable {
    public let thread: ThreadViewModel

    public let messageId: String?
    public let messageDate: Date?

    public let snippet: String?

    private let sortKey: SortKey

    init(thread: ThreadViewModel, sortKey: SortKey, messageId: String? = nil, messageDate: Date? = nil, snippet: String? = nil) {
        self.thread = thread
        self.sortKey = sortKey
        self.messageId = messageId
        self.messageDate = messageDate
        self.snippet = snippet
    }

    // MARK: Comparable

    public static func < (lhs: ConversationSearchResult, rhs: ConversationSearchResult) -> Bool {
        return lhs.sortKey < rhs.sortKey
    }

    // MARK: Equatable

    public static func == (lhs: ConversationSearchResult, rhs: ConversationSearchResult) -> Bool {
        return lhs.thread.threadRecord.uniqueId == rhs.thread.threadRecord.uniqueId &&
            lhs.messageId == rhs.messageId
    }
}

@objc
public class ContactSearchResult: NSObject, Comparable {
    public let signalAccount: SignalAccount
    private let comparableName: String

    public var recipientAddress: SignalServiceAddress {
        return signalAccount.recipientAddress
    }

    init(signalAccount: SignalAccount, transaction: SDSAnyReadTransaction) {
        self.signalAccount = signalAccount
        self.comparableName = Environment.shared.contactsManager.comparableName(for: signalAccount, transaction: transaction)
    }

    // MARK: Comparable

    public static func < (lhs: ContactSearchResult, rhs: ContactSearchResult) -> Bool {
        var comparisonResult = lhs.comparableName.caseInsensitiveCompare(rhs.comparableName)

        if comparisonResult == .orderedSame {
            comparisonResult = lhs.recipientAddress.stringForDisplay.compare(rhs.recipientAddress.stringForDisplay)
        }

        return comparisonResult == .orderedAscending
    }

    // MARK: Equatable

    public static func == (lhs: ContactSearchResult, rhs: ContactSearchResult) -> Bool {
        return lhs.recipientAddress == rhs.recipientAddress
    }
}

public class HomeScreenSearchResultSet: NSObject {
    public let searchText: String
    public let conversations: [ConversationSearchResult<ConversationSortKey>]
    public let contacts: [ContactSearchResult]
    public let messages: [ConversationSearchResult<MessageSortKey>]

    public init(searchText: String, conversations: [ConversationSearchResult<ConversationSortKey>], contacts: [ContactSearchResult], messages: [ConversationSearchResult<MessageSortKey>]) {
        self.searchText = searchText
        self.conversations = conversations
        self.contacts = contacts
        self.messages = messages
    }

    public class var empty: HomeScreenSearchResultSet {
        return HomeScreenSearchResultSet(searchText: "", conversations: [], contacts: [], messages: [])
    }

    public var isEmpty: Bool {
        return conversations.isEmpty && contacts.isEmpty && messages.isEmpty
    }
}

@objc
public class GroupSearchResult: NSObject, Comparable {
    public let thread: ThreadViewModel

    private let sortKey: ConversationSortKey

    init(thread: ThreadViewModel, sortKey: ConversationSortKey) {
        self.thread = thread
        self.sortKey = sortKey
    }

    // MARK: Comparable

    public static func < (lhs: GroupSearchResult, rhs: GroupSearchResult) -> Bool {
        return lhs.sortKey < rhs.sortKey
    }

    // MARK: Equatable

    public static func == (lhs: GroupSearchResult, rhs: GroupSearchResult) -> Bool {
        return lhs.thread.threadRecord.uniqueId == rhs.thread.threadRecord.uniqueId
    }
}

@objc
public class ComposeScreenSearchResultSet: NSObject {

    @objc
    public let searchText: String

    @objc
    public let groups: [GroupSearchResult]

    @objc
    public var groupThreads: [TSGroupThread] {
        return groups.compactMap { $0.thread.threadRecord as? TSGroupThread }
    }

    @objc
    public let signalContacts: [ContactSearchResult]

    @objc
    public var signalAccounts: [SignalAccount] {
        return signalContacts.map { $0.signalAccount }
    }

    public init(searchText: String, groups: [GroupSearchResult], signalContacts: [ContactSearchResult]) {
        self.searchText = searchText
        self.groups = groups
        self.signalContacts = signalContacts
    }

    @objc
    public static let empty = ComposeScreenSearchResultSet(searchText: "", groups: [], signalContacts: [])

    @objc
    public var isEmpty: Bool {
        return groups.isEmpty && signalContacts.isEmpty
    }
}

@objc
public class MessageSearchResult: NSObject, Comparable {

    public let messageId: String
    public let sortId: UInt64

    init(messageId: String, sortId: UInt64) {
        self.messageId = messageId
        self.sortId = sortId
    }

    // MARK: - Comparable

    public static func < (lhs: MessageSearchResult, rhs: MessageSearchResult) -> Bool {
        return lhs.sortId < rhs.sortId
    }
}

@objc
public class ConversationScreenSearchResultSet: NSObject {

    @objc
    public let searchText: String

    @objc
    public let messages: [MessageSearchResult]

    @objc
    public lazy var messageSortIds: [UInt64] = {
        return messages.map { $0.sortId }
    }()

    // MARK: Static members

    public static let empty: ConversationScreenSearchResultSet = ConversationScreenSearchResultSet(searchText: "", messages: [])

    // MARK: Init

    public init(searchText: String, messages: [MessageSearchResult]) {
        self.searchText = searchText
        self.messages = messages
    }

    // MARK: - CustomDebugStringConvertible

    override public var debugDescription: String {
        return "ConversationScreenSearchResultSet(searchText: \(searchText), messages: [\(messages.count) matches])"
    }
}

@objc
public class FullTextSearcher: NSObject {

    @objc
    public static let kDefaultMaxResults: UInt = 500

    // MARK: - Dependencies

    private var contactsManager: OWSContactsManager {
        return Environment.shared.contactsManager
    }

    // MARK: - 

    private let finder: FullTextSearchFinder

    @objc
    public static let shared: FullTextSearcher = FullTextSearcher()
    override private init() {
        finder = FullTextSearchFinder()
        super.init()
    }

    @objc
    public func searchForComposeScreen(searchText: String,
                                       maxResults: UInt = kDefaultMaxResults,
                                       transaction: SDSAnyReadTransaction) -> ComposeScreenSearchResultSet {

        var signalContacts: [ContactSearchResult] = []
        var groups: [GroupSearchResult] = []

        var count: UInt = 0
        self.finder.enumerateObjects(searchText: searchText, transaction: transaction) { (match: Any, _: String?, stop: UnsafeMutablePointer<ObjCBool>) in

            count += 1
            guard count < maxResults else {
                stop.pointee = true
                return
            }

            switch match {
            case let signalAccount as SignalAccount:
                let searchResult = ContactSearchResult(signalAccount: signalAccount, transaction: transaction)
                signalContacts.append(searchResult)
            case let groupThread as TSGroupThread:
                let sortKey = ConversationSortKey(isContactThread: false,
                                                  creationDate: groupThread.creationDate,
                                                  lastInteractionRowId: groupThread.lastInteractionRowId)
                let threadViewModel = ThreadViewModel(thread: groupThread, transaction: transaction)
                let searchResult = GroupSearchResult(thread: threadViewModel, sortKey: sortKey)
                groups.append(searchResult)
            case is TSContactThread:
                // not included in compose screen results
                break
            case is TSMessage:
                // not included in compose screen results
                break
            default:
                owsFailDebug("unhandled item: \(match)")
            }
        }

        if matchesNoteToSelf(searchText: searchText, transaction: transaction) {
            if !signalContacts.contains(where: { $0.signalAccount.recipientAddress.isLocalAddress }) {
                if let localAddress = TSAccountManager.localAddress {
                    let localAccount = SignalAccount(address: localAddress)
                    let localResult = ContactSearchResult(signalAccount: localAccount, transaction: transaction)
                    signalContacts.append(localResult)
                } else {
                    owsFailDebug("localAddress was unexpectedly nil")
                }
            }
        }

        // Order contact results by display name.
        signalContacts.sort()

        // Order the conversation and message results in reverse chronological order.
        // The contact results are pre-sorted by display name.
        groups.sort(by: >)

        return ComposeScreenSearchResultSet(searchText: searchText, groups: groups, signalContacts: signalContacts)
    }

    func matchesNoteToSelf(searchText: String, transaction: SDSAnyReadTransaction) -> Bool {
        guard let localAddress = TSAccountManager.localAddress else {
            return false
        }
        let noteToSelfText = self.conversationIndexingString(address: localAddress, transaction: transaction)
        let matchedTerm = searchText.split(separator: " ").first { term in
            return noteToSelfText.contains(term)
        }

        return matchedTerm != nil
    }

    public func searchForHomeScreen(searchText: String,
                                    maxResults: UInt = kDefaultMaxResults,
                                    transaction: SDSAnyReadTransaction) -> HomeScreenSearchResultSet {

        var conversations: [ConversationSearchResult<ConversationSortKey>] = []
        var contacts: [ContactSearchResult] = []
        var messages: [ConversationSearchResult<MessageSortKey>] = []

        var existingConversationAddresses: Set<SignalServiceAddress> = Set()

        var threadCache = [String: TSThread]()
        let getThread: (String) -> TSThread? = { threadUniqueId in
            if let thread = threadCache[threadUniqueId] {
                return thread
            }
            guard let thread = TSThread.anyFetch(uniqueId: threadUniqueId, transaction: transaction) else {
                return nil
            }
            threadCache[threadUniqueId] = thread
            return thread
        }

        var threadViewModelCache = [String: ThreadViewModel]()
        let getThreadViewModel: (TSThread) -> ThreadViewModel = { thread in
            if let threadViewModel = threadViewModelCache[thread.uniqueId] {
                return threadViewModel
            }
            let threadViewModel = ThreadViewModel(thread: thread, transaction: transaction)
            threadViewModelCache[thread.uniqueId] = threadViewModel
            return threadViewModel
        }

        var count: UInt = 0
        self.finder.enumerateObjects(searchText: searchText, transaction: transaction) { (match: Any, snippet: String?, stop: UnsafeMutablePointer<ObjCBool>) in

            count += 1
            guard count < maxResults else {
                stop.pointee = true
                return
            }

            if let thread = match as? TSThread {
                let threadViewModel = getThreadViewModel(thread)
                let sortKey = ConversationSortKey(isContactThread: thread is TSContactThread,
                                                  creationDate: thread.creationDate,
                                                  lastInteractionRowId: thread.lastInteractionRowId)
                let searchResult = ConversationSearchResult(thread: threadViewModel, sortKey: sortKey)
                switch thread {
                case is TSGroupThread:
                    conversations.append(searchResult)
                case let contactThread as TSContactThread:
                    if contactThread.shouldThreadBeVisible {
                        existingConversationAddresses.insert(contactThread.contactAddress)
                        conversations.append(searchResult)
                    }
                default:
                    owsFailDebug("unexpected thread: \(type(of: thread))")
                }
            } else if let message = match as? TSMessage {
                guard let thread = getThread(message.uniqueThreadId) else {
                    owsFailDebug("Missing thread: \(type(of: message))")
                    return
                }

                let threadViewModel = getThreadViewModel(thread)
                let sortKey = message.sortId
                let searchResult = ConversationSearchResult(thread: threadViewModel,
                                                            sortKey: sortKey,
                                                            messageId: message.uniqueId,
                                                            messageDate: NSDate.ows_date(withMillisecondsSince1970: message.timestamp),
                                                            snippet: snippet)

                messages.append(searchResult)
            } else if let signalAccount = match as? SignalAccount {
                let searchResult = ContactSearchResult(signalAccount: signalAccount, transaction: transaction)
                contacts.append(searchResult)
            } else {
                owsFailDebug("unhandled item: \(match)")
            }
        }

        if matchesNoteToSelf(searchText: searchText, transaction: transaction) {
            if !contacts.contains(where: { $0.signalAccount.recipientAddress.isLocalAddress }) {
                if let localAddress = TSAccountManager.localAddress {
                    let localAccount = SignalAccount(address: localAddress)
                    let localResult = ContactSearchResult(signalAccount: localAccount, transaction: transaction)
                    contacts.append(localResult)
                } else {
                    owsFailDebug("localAddress was unexpectedly nil")
                }
            }
        }

        // Only show contacts which were not included in an existing 1:1 conversation.
        var otherContacts: [ContactSearchResult] = contacts.filter { !existingConversationAddresses.contains($0.recipientAddress) }

        // Order the conversation and message results in reverse chronological order.
        // The contact results are pre-sorted by display name.
        conversations.sort(by: >)
        messages.sort(by: >)
        // Order "other" contact results by display name.
        otherContacts.sort()

        return HomeScreenSearchResultSet(searchText: searchText, conversations: conversations, contacts: otherContacts, messages: messages)
    }

    public func searchWithinConversation(thread: TSThread,
                                         searchText: String,
                                         maxResults: UInt = kDefaultMaxResults,
                                         transaction: SDSAnyReadTransaction) -> ConversationScreenSearchResultSet {

        var messages: [MessageSearchResult] = []

        var count: UInt = 0
        self.finder.enumerateObjects(searchText: searchText, transaction: transaction) { (match: Any, _: String?, stop: UnsafeMutablePointer<ObjCBool>) in

            count += 1
            guard count < maxResults else {
                stop.pointee = true
                return
            }

            if let message = match as? TSMessage {
                guard message.uniqueThreadId == thread.uniqueId else {
                    return
                }

                let messageId = message.uniqueId
                let searchResult = MessageSearchResult(messageId: messageId, sortId: message.sortId)
                messages.append(searchResult)
            }
        }

        // We want most recent first
        messages.sort(by: >)

        return ConversationScreenSearchResultSet(searchText: searchText, messages: messages)
    }

    @objc(filterThreads:withSearchText:transaction:)
    public func filterThreads(_ threads: [TSThread], searchText: String, transaction: SDSAnyReadTransaction) -> [TSThread] {
        guard searchText.trimmingCharacters(in: .whitespacesAndNewlines).count > 0 else {
            return threads
        }

        return threads.filter { thread in
            switch thread {
            case let groupThread as TSGroupThread:
                return self.groupThreadSearcher.matches(item: groupThread, query: searchText, transaction: transaction)
            case let contactThread as TSContactThread:
                return self.contactThreadSearcher.matches(item: contactThread, query: searchText, transaction: transaction)
            default:
                owsFailDebug("Unexpected thread type: \(thread)")
                return false
            }
        }
    }

    @objc(filterGroupThreads:withSearchText:transaction:)
    public func filterGroupThreads(_ groupThreads: [TSGroupThread], searchText: String, transaction: SDSAnyReadTransaction) -> [TSGroupThread] {
        guard searchText.trimmingCharacters(in: .whitespacesAndNewlines).count > 0 else {
            return groupThreads
        }

        return groupThreads.filter { groupThread in
            return self.groupThreadSearcher.matches(item: groupThread, query: searchText, transaction: transaction)
        }
    }

    @objc(filterSignalAccounts:withSearchText:transaction:)
    public func filterSignalAccounts(_ signalAccounts: [SignalAccount], searchText: String, transaction: SDSAnyReadTransaction) -> [SignalAccount] {
        guard searchText.trimmingCharacters(in: .whitespacesAndNewlines).count > 0 else {
            return signalAccounts
        }

        return signalAccounts.filter { signalAccount in
            self.signalAccountSearcher.matches(item: signalAccount, query: searchText, transaction: transaction)
        }
    }

    // MARK: Searchers

    private lazy var groupThreadSearcher: Searcher<TSGroupThread> = Searcher { (groupThread: TSGroupThread, transaction: SDSAnyReadTransaction) in
        let groupName = groupThread.groupModel.groupName
        let memberStrings = groupThread.groupModel.groupMembers.map { address in
            self.indexingString(address: address, transaction: transaction)
        }.joined(separator: " ")

        return "\(memberStrings) \(groupName ?? "")"
    }

    private lazy var contactThreadSearcher: Searcher<TSContactThread> = Searcher { (contactThread: TSContactThread, transaction: SDSAnyReadTransaction) in
        let recipientAddress = contactThread.contactAddress
        return self.conversationIndexingString(address: recipientAddress, transaction: transaction)
    }

    private lazy var signalAccountSearcher: Searcher<SignalAccount> = Searcher { (signalAccount: SignalAccount, transaction: SDSAnyReadTransaction) in
        let recipientAddress = signalAccount.recipientAddress
        return self.conversationIndexingString(address: recipientAddress, transaction: transaction)
    }

    private func conversationIndexingString(address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> String {
        var result = self.indexingString(address: address, transaction: transaction)

        if IsNoteToSelfEnabled(), address.isLocalAddress {
            result += " \(MessageStrings.noteToSelf)"
        }

        return result
    }

    private func indexingString(address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> String {
        let displayName = contactsManager.displayName(for: address, transaction: transaction)

        return "\(address.phoneNumber ?? "") \(displayName)"
    }
}
