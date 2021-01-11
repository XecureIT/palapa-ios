//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public extension SSKProtoGroupDetails {
    var memberAddresses: [SignalServiceAddress] {
        // Parse legacy pre-uuid group members that are not represented in the members list
        let legacyMembers = membersE164.filter { e164 in members.first { $0.e164 == e164 } == nil }.map { SignalServiceAddress(phoneNumber: $0) }

        return members.map { SignalServiceAddress(uuidString: $0.uuid, phoneNumber: $0.e164) } + legacyMembers
    }
    
    var ownerAddress: SignalServiceAddress? {
        return (owner != nil) ? SignalServiceAddress(phoneNumber: owner!) : nil
    }
    
    var adminAddresses: [SignalServiceAddress] {
        // Parse legacy pre-uuid group members that are not represented in the members list
        let legacyAdmins = adminsE164.filter { e164 in admins.first { $0.e164 == e164 } == nil }.map { SignalServiceAddress(phoneNumber: $0) }

        return admins.map { SignalServiceAddress(uuidString: $0.uuid, phoneNumber: $0.e164) } + legacyAdmins
    }
}

@objc
public extension SSKProtoGroupContext {
    var memberAddresses: [SignalServiceAddress] {
        // Parse legacy pre-uuid group members that are not represented in the members list
        let legacyMembers = membersE164.filter { e164 in members.first { $0.e164 == e164 } == nil }.map { SignalServiceAddress(phoneNumber: $0) }

        return members.map { SignalServiceAddress(uuidString: $0.uuid, phoneNumber: $0.e164) } + legacyMembers
    }
    
    var ownerAddress: SignalServiceAddress? {
        return (owner != nil) ? SignalServiceAddress(phoneNumber: owner!) : nil
    }
    
    var adminAddresses: [SignalServiceAddress] {
        // Parse legacy pre-uuid group members that are not represented in the members list
        let legacyAdmins = adminsE164.filter { e164 in admins.first { $0.e164 == e164 } == nil }.map { SignalServiceAddress(phoneNumber: $0) }

        return admins.map { SignalServiceAddress(uuidString: $0.uuid, phoneNumber: $0.e164) } + legacyAdmins
    }
}
