//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

public struct GroupDetails {
    public let groupId: Data
    public let name: String?
    public let memberAddresses: [SignalServiceAddress]
    public let conversationColorName: String?
    public let isBlocked: Bool
    public let expireTimer: UInt32
    public let avatarData: Data?
    public let isArchived: Bool?
    public let inboxSortOrder: UInt32?
    public let ownerAddress: SignalServiceAddress?
    public let adminAddresses: [SignalServiceAddress]
}

public class GroupsInputStream {
    var inputStream: ChunkedInputStream

    public init(inputStream: ChunkedInputStream) {
        self.inputStream = inputStream
    }

    public func decodeGroup() throws -> GroupDetails? {
        guard !inputStream.isEmpty else {
            return nil
        }

        var groupDataLength: UInt32 = 0
        try inputStream.decodeSingularUInt32Field(value: &groupDataLength)

        var groupData: Data = Data()
        try inputStream.decodeData(value: &groupData, count: Int(groupDataLength))

        let groupDetails = try SSKProtoGroupDetails.parseData(groupData)

        var avatarData: Data?
        if let avatar = groupDetails.avatar {
            var decodedData = Data()
            try inputStream.decodeData(value: &decodedData, count: Int(avatar.length))
            if decodedData.count > 0 {
                avatarData = decodedData
            }
        }

        return GroupDetails(groupId: groupDetails.id,
                            name: groupDetails.name,
                            memberAddresses: groupDetails.memberAddresses,
                            conversationColorName: groupDetails.color,
                            isBlocked: groupDetails.blocked,
                            expireTimer: groupDetails.expireTimer,
                            avatarData: avatarData,
                            isArchived: groupDetails.hasArchived ? groupDetails.archived : nil,
                            inboxSortOrder: groupDetails.hasInboxPosition ? groupDetails.inboxPosition : nil,
                            ownerAddress: groupDetails.ownerAddress,
                            adminAddresses: groupDetails.adminAddresses)
    }
}
