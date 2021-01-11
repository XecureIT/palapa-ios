//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import XCTest
import Contacts

class GroupAndContactStreamTest: SignalBaseTest {

    let outputContactSyncData = "IQoMKzEzMjMxMTExMTExEgdBbGljZS0xIgRibHVlQABYADkSB0FsaWNlLTIiBGJsdWVAAEokMzFDRTE0MTItOUEyOC00RTZGLUI0RUUtMjIyMjIyMjIyMjIyWABHCgwrMTMyMTMzMzMzMzMSB0FsaWNlLTMiBGJsdWVAAEokMUQ0QUIwNDUtODhGQi00QzRFLTlGNkEtMzMzMzMzMzMzMzMzWAA="

    func test_writeContactSync() throws {
        let signalAccounts = [
            SignalAccount(address: .init(phoneNumber: "+13231111111")),
            SignalAccount(address: .init(uuidString: "31ce1412-9a28-4e6f-b4ee-222222222222")),
            SignalAccount(address: .init(uuidString: "1d4ab045-88fb-4c4e-9f6a-333333333333", phoneNumber: "+13213333333"))
        ]

        let streamData = try buildContactSyncData(signalAccounts: signalAccounts)

        XCTAssertEqual(streamData.base64EncodedString(), outputContactSyncData)
    }

    func test_readContactSync() throws {
        var contacts: [ContactDetails] = []

        let data = Data(base64Encoded: outputContactSyncData)!
        try data.withUnsafeBytes { bufferPtr in
            if let baseAddress = bufferPtr.baseAddress, bufferPtr.count > 0 {
                let pointer = baseAddress.assumingMemoryBound(to: UInt8.self)
                let inputStream = ChunkedInputStream(forReadingFrom: pointer, count: bufferPtr.count)
                let contactStream = ContactsInputStream(inputStream: inputStream)
                while let nextContact = try contactStream.decodeContact() {
                    contacts.append(nextContact)
                }
            }
        }

        guard contacts.count == 3 else {
            XCTFail("unexpected contact count: \(contacts.count)")
            return
        }

        do {
            let contact = contacts[0]
            XCTAssertEqual("+13231111111", contact.address.phoneNumber)
            XCTAssertNil(contact.address.uuid)
            XCTAssertEqual("Alice-1", contact.name)
            XCTAssertEqual("blue", contact.conversationColorName)
            XCTAssertNil(contact.verifiedProto)
            XCTAssertNil(contact.profileKey)
            XCTAssertEqual(false, contact.isBlocked)
            XCTAssertEqual(0, contact.expireTimer)
            XCTAssertNil(contact.avatarData)
            XCTAssertEqual(false, contact.isArchived)
            XCTAssertNil(contact.inboxSortOrder)
        }

        do {
            let contact = contacts[1]
            XCTAssertNil(contact.address.phoneNumber)
            XCTAssertEqual("31CE1412-9A28-4E6F-B4EE-222222222222", contact.address.uuid?.uuidString)
            XCTAssertEqual("Alice-2", contact.name)
            XCTAssertEqual("blue", contact.conversationColorName)
            XCTAssertNil(contact.verifiedProto)
            XCTAssertNil(contact.profileKey)
            XCTAssertEqual(false, contact.isBlocked)
            XCTAssertEqual(0, contact.expireTimer)
            XCTAssertNil(contact.avatarData)
            XCTAssertEqual(false, contact.isArchived)
            XCTAssertNil(contact.inboxSortOrder)
        }

        do {
            let contact = contacts[2]
            XCTAssertEqual("+13213333333", contact.address.phoneNumber)
            XCTAssertEqual("1D4AB045-88FB-4C4E-9F6A-333333333333", contact.address.uuid?.uuidString)
            XCTAssertEqual("Alice-3", contact.name)
            XCTAssertEqual("blue", contact.conversationColorName)
            XCTAssertNil(contact.verifiedProto)
            XCTAssertNil(contact.profileKey)
            XCTAssertEqual(false, contact.isBlocked)
            XCTAssertEqual(0, contact.expireTimer)
            XCTAssertNil(contact.avatarData)
            XCTAssertEqual(false, contact.isArchived)
            XCTAssertNil(contact.inboxSortOrder)
        }
    }

    let outputGroupSyncData = "pwEKEHNddRc9sZVW92G7XH8DdEgaDCsxMzIxMzIxNDMyMRoMKzEzMjEzMjE0MzIzMAA6BWJyb3duSg4SDCsxMzIxMzIxNDMyMUo0CiQxRDRBQjA0NS04OEZCLTRDNEUtOUY2QS1GOTIxMTI0QkQ1MjkSDCsxMzIxMzIxNDMyM0omCiQzMUNFMTQxMi05QTI4LTRFNkYtQjRFRS1BMjVDMzE3OUQwODVYAJABChBzbbYXPbGVVvdhu1x/A3RIEglCb29rIENsdWIaDCsxMzIxMzIxNDMyMRoMKzE1NTUzMjE0MzIzMAA6CWJsdWVfZ3JleUoOEgwrMTMyMTMyMTQzMjFKNAokNTU1NTU1NTUtODhGQi00QzRFLTlGNkEtRjkyMTEyNEJENTI5EgwrMTU1NTMyMTQzMjNQAVgBiwEKEHN99xc9sZVW92G7XH8DdEgSCUNvb2sgQmx1YhoMKzEzMjEzMjEzMzMzGgwrMTU1NTMyMTIyMjIwADoEYmx1ZUoOEgwrMTMyMTMyMTMzMzNKNAokNTU1NTU1NTUtODhGQi00QzRFLTlGNkEtMjIyMjIyMjIyMjIyEgwrMTU1NTMyMTIyMjJQAFgB"
    func test_writeGroupSync() throws {
        let group1: TSGroupThread = {
            let groupId = Data(base64Encoded: "c111Fz2xlVb3YbtcfwN0SA==")!
            let groupMembers: [SignalServiceAddress] = [
                .init(phoneNumber: "+13213214321"),
                .init(uuidString: "31ce1412-9a28-4e6f-b4ee-a25c3179d085"),
                .init(uuidString: "1d4ab045-88fb-4c4e-9f6a-f921124bd529", phoneNumber: "+13213214323")
            ]

            var thread: TSGroupThread!
            write { transaction in
                thread = try! GroupManager.createGroupForTests(transaction: transaction,
                                                               members: groupMembers,
                                                               groupId: groupId)

                thread.anyInsert(transaction: transaction)
                thread.updateConversationColorName(.burlap, transaction: transaction)
            }
            return thread
        }()

        let group2: TSGroupThread = {
            let groupId = Data(base64Encoded: "c222Fz2xlVb3YbtcfwN0SA==")!
            let groupMembers: [SignalServiceAddress] = [
                .init(phoneNumber: "+13213214321"),
                .init(uuidString: "55555555-88fb-4c4e-9f6a-f921124bd529", phoneNumber: "+15553214323")
            ]

            var thread: TSGroupThread!
            write {
                thread = try! GroupManager.createGroupForTests(transaction: $0,
                                                               members: groupMembers,
                                                               name: "Book Club",
                                                               groupId: groupId)
                thread.shouldThreadBeVisible = true
                thread.anyOverwritingUpdate(transaction: $0)
                thread.updateConversationColorName(.taupe, transaction: $0)
                thread.archiveThread(with: $0)
            }
            return thread
        }()

        let group3: TSGroupThread = {
            let groupId = Data(base64Encoded: "c333Fz2xlVb3YbtcfwN0SA==")!
            let groupMembers: [SignalServiceAddress] = [
                .init(phoneNumber: "+13213213333"),
                .init(uuidString: "55555555-88fb-4c4e-9f6a-222222222222", phoneNumber: "+15553212222")
            ]

            var thread: TSGroupThread!
            write { transaction in
                thread = try! GroupManager.createGroupForTests(transaction: transaction,
                                                               members: groupMembers,
                                                               name: "Cook Blub",
                                                               groupId: groupId)
                thread.shouldThreadBeVisible = true
                thread.anyOverwritingUpdate(transaction: transaction)
                thread.updateConversationColorName(.blue, transaction: transaction)

                let messageFactory = OutgoingMessageFactory()
                messageFactory.threadCreator = { _ in return thread }
                _ = messageFactory.create(transaction: transaction)

                thread.archiveThread(with: transaction)
            }
            return thread
        }()

        let streamData = try buildGroupSyncData(groupThreads: [group1, group2, group3])

        XCTAssertEqual(streamData.base64EncodedString(), outputGroupSyncData)
    }

    func test_readGroupSync() throws {
        var groups: [GroupDetails] = []

        let data = Data(base64Encoded: outputGroupSyncData)!
        try data.withUnsafeBytes { bufferPtr in
            if let baseAddress = bufferPtr.baseAddress, bufferPtr.count > 0 {
                let pointer = baseAddress.assumingMemoryBound(to: UInt8.self)
                let inputStream = ChunkedInputStream(forReadingFrom: pointer, count: bufferPtr.count)
                let groupStream = GroupsInputStream(inputStream: inputStream)
                while let nextGroup = try groupStream.decodeGroup() {
                    groups.append(nextGroup)
                }
            }
        }

        guard groups.count == 3 else {
            XCTFail("unexpected group count: \(groups.count)")
            return
        }

        do {
            let group = groups[0]
            XCTAssertEqual(group.groupId, Data(base64Encoded: "c111Fz2xlVb3YbtcfwN0SA==")!)
            XCTAssertEqual(group.name, nil)
            XCTAssertEqual(group.memberAddresses, [
                SignalServiceAddress(phoneNumber: "+13213214321"),
                SignalServiceAddress(uuidString: "31ce1412-9a28-4e6f-b4ee-a25c3179d085"),
                SignalServiceAddress(uuidString: "1d4ab045-88fb-4c4e-9f6a-f921124bd529", phoneNumber: "+13213214323")
            ])

            XCTAssertEqual(group.conversationColorName, ConversationColorName.burlap.rawValue)
            XCTAssertEqual(group.isBlocked, false)
            XCTAssertEqual(group.expireTimer, 0)
            XCTAssertEqual(group.avatarData, nil)
            XCTAssertEqual(false, group.isArchived)
            XCTAssertNil(group.inboxSortOrder)
        }

        do {
            let group = groups[1]
            XCTAssertEqual(group.groupId, Data(base64Encoded: "c222Fz2xlVb3YbtcfwN0SA==")!)
            XCTAssertEqual(group.name, "Book Club")
            XCTAssertEqual(group.memberAddresses, [
                SignalServiceAddress(phoneNumber: "+13213214321"),
                SignalServiceAddress(uuidString: "55555555-88fb-4c4e-9f6a-f921124bd529", phoneNumber: "+15553214323")
            ])
            XCTAssertEqual(group.conversationColorName, ConversationColorName.taupe.rawValue)
            XCTAssertEqual(group.isBlocked, false)
            XCTAssertEqual(group.expireTimer, 0)
            XCTAssertEqual(group.avatarData, nil)
            XCTAssertEqual(true, group.isArchived)
            XCTAssertEqual(1, group.inboxSortOrder)
        }

        do {
            let group = groups[2]
            XCTAssertEqual(group.groupId, Data(base64Encoded: "c333Fz2xlVb3YbtcfwN0SA==")!)
            XCTAssertEqual(group.name, "Cook Blub")
            XCTAssertEqual(group.memberAddresses, [
                SignalServiceAddress(phoneNumber: "+13213213333"),
                SignalServiceAddress(uuidString: "55555555-88FB-4C4E-9F6A-222222222222", phoneNumber: "+15553212222")
                ])
            XCTAssertEqual(group.conversationColorName, ConversationColorName.blue.rawValue)
            XCTAssertEqual(group.isBlocked, false)
            XCTAssertEqual(group.expireTimer, 0)
            XCTAssertEqual(group.avatarData, nil)
            XCTAssertEqual(true, group.isArchived)
            XCTAssertEqual(0, group.inboxSortOrder)
        }
    }

    func buildContactSyncData(signalAccounts: [SignalAccount]) throws -> Data {
        let contactsManager = TestContactsManager()
        let dataOutputStream = OutputStream(toMemory: ())
        dataOutputStream.open()
        let contactsOutputStream = OWSContactsOutputStream(outputStream: dataOutputStream)

        for signalAccount in signalAccounts {
            let contactFactory = ContactFactory()
            contactFactory.fullNameBuilder = {
                "Alice-\(signalAccount.recipientAddress.serviceIdentifier!.suffix(1))"
            }
            contactFactory.cnContactIdBuilder = { "123" }
            contactFactory.uniqueIdBuilder = { "123" }

            signalAccount.contact = try contactFactory.build()

            contactsOutputStream.write(signalAccount,
                                       recipientIdentity: nil,
                                       profileKeyData: nil,
                                       contactsManager: contactsManager,
                                       conversationColorName: ConversationColorName.blue.rawValue,
                                       disappearingMessagesConfiguration: nil,
                                       isArchived: false,
                                       inboxPosition: nil)
        }

        dataOutputStream.close()
        guard !contactsOutputStream.hasError else {
            throw OWSAssertionError("contactsOutputStream.hasError")
        }

        return dataOutputStream.property(forKey: .dataWrittenToMemoryStreamKey) as! Data
    }

    func buildGroupSyncData(groupThreads: [TSGroupThread]) throws -> Data {
        let dataOutputStream = OutputStream(toMemory: ())
        dataOutputStream.open()
        let groupsOutputStream = OWSGroupsOutputStream(outputStream: dataOutputStream)

        read { transaction in
            for groupThread in groupThreads {
                groupsOutputStream.writeGroup(groupThread, transaction: transaction)
            }
        }

        dataOutputStream.close()
        guard !groupsOutputStream.hasError else {
            throw OWSAssertionError("contactsOutputStream.hasError")
        }

        return dataOutputStream.property(forKey: .dataWrittenToMemoryStreamKey) as! Data
    }
}

class TestContactsManager: NSObject, ContactsManagerProtocol {
    func comparableName(for signalAccount: SignalAccount, transaction: SDSAnyReadTransaction) -> String {
        return signalAccount.recipientAddress.stringForDisplay
    }

    func displayName(for address: SignalServiceAddress) -> String {
        return address.stringForDisplay
    }

    func displayName(for address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> String {
        return address.stringForDisplay
    }

    func displayName(for signalAccount: SignalAccount) -> String {
        return signalAccount.recipientAddress.stringForDisplay
    }

    func displayName(for thread: TSThread, transaction: SDSAnyReadTransaction) -> String {
        return "Fake Name"
    }

    func displayNameWithSneakyTransaction(thread: TSThread) -> String {
        return "Fake Name"
    }

    func signalAccounts() -> [SignalAccount] {
        return []
    }

    func isSystemContact(phoneNumber: String) -> Bool {
        return true
    }

    func isSystemContact(address: SignalServiceAddress) -> Bool {
        return true
    }

    func isSystemContact(withSignalAccount phoneNumber: String) -> Bool {
        return true
    }

    func compare(signalAccount left: SignalAccount, with right: SignalAccount) -> ComparisonResult {
        return .orderedSame
    }

    func cnContact(withId contactId: String?) -> CNContact? {
        return nil
    }

    func avatarData(forCNContactId contactId: String?) -> Data? {
        return nil
    }

    func avatarImage(forCNContactId contactId: String?) -> UIImage? {
        return nil
    }
}
