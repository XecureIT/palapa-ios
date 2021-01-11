//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

public struct ContactDetails {
    public let address: SignalServiceAddress
    public let name: String?
    public let conversationColorName: String?
    public let verifiedProto: SSKProtoVerified?
    public let profileKey: Data?
    public let isBlocked: Bool
    public let expireTimer: UInt32
    public let avatarData: Data?
    public let isArchived: Bool?
    public let inboxSortOrder: UInt32?
}

public class ContactsInputStream {
    var inputStream: ChunkedInputStream

    public init(inputStream: ChunkedInputStream) {
        self.inputStream = inputStream
    }

    public func decodeContact() throws -> ContactDetails? {
        guard !inputStream.isEmpty else {
            return nil
        }

        var contactDataLength: UInt32 = 0
        try inputStream.decodeSingularUInt32Field(value: &contactDataLength)

        var contactData: Data = Data()
        try inputStream.decodeData(value: &contactData, count: Int(contactDataLength))

        let contactDetails = try SSKProtoContactDetails.parseData(contactData)

        var avatarData: Data?
        if let avatar = contactDetails.avatar {
            var decodedData = Data()
            try inputStream.decodeData(value: &decodedData, count: Int(avatar.length))
            if decodedData.count > 0 {
                avatarData = decodedData
            }
        }

        let address = SignalServiceAddress(uuidString: contactDetails.uuid, phoneNumber: contactDetails.number)
        guard address.isValid else {
            throw OWSAssertionError("address was unexpectedly invalid")
        }

        return ContactDetails(address: address,
                              name: contactDetails.name,
                              conversationColorName: contactDetails.color,
                              verifiedProto: contactDetails.verified,
                              profileKey: contactDetails.profileKey,
                              isBlocked: contactDetails.blocked,
                              expireTimer: contactDetails.expireTimer,
                              avatarData: avatarData,
                              isArchived: contactDetails.hasArchived ? contactDetails.archived : nil,
                              inboxSortOrder: contactDetails.hasInboxPosition ? contactDetails.inboxPosition : nil)
    }
}
