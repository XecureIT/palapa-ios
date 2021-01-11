//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

// Helpers for building and restoring contact records.

extension StorageServiceProtoContactRecord {

    // MARK: - Dependencies

    static var profileManager: OWSProfileManager {
        return .shared()
    }

    var profileManager: OWSProfileManager {
        return .shared()
    }

    static var blockingManager: OWSBlockingManager {
        return .shared()
    }

    var blockingManager: OWSBlockingManager {
        return .shared()
    }

    static var identityManager: OWSIdentityManager {
        return .shared()
    }

    var identityManager: OWSIdentityManager {
        return .shared()
    }

    // MARK: -

    static func build(
        for accountId: AccountId,
        transaction: SDSAnyReadTransaction
    ) throws -> StorageServiceProtoContactRecord {
        guard let address = OWSAccountIdFinder().address(forAccountId: accountId, transaction: transaction) else {
            throw StorageService.StorageError.assertion
        }

        let builder = StorageServiceProtoContactRecord.builder()

        if let phoneNumber = address.phoneNumber {
            builder.setServiceE164(phoneNumber)
        }

        if let uuidString = address.uuidString {
            builder.setServiceUuid(uuidString)
        }

        let isInWhitelist = profileManager.isUser(inProfileWhitelist: address, transaction: transaction)
        let profileKey = profileManager.profileKeyData(for: address, transaction: transaction)
        let profileName = profileManager.profileName(for: address, transaction: transaction)

        builder.setBlocked(blockingManager.isAddressBlocked(address))
        builder.setWhitelisted(isInWhitelist)

        // Identity
        let identityBuilder = StorageServiceProtoContactRecordIdentity.builder()

        if let identityKey = identityManager.identityKey(for: address, transaction: transaction) {
            identityBuilder.setKey(identityKey)
        }

        let verificationState = identityManager.verificationState(for: address, transaction: transaction)
        identityBuilder.setState(.from(verificationState))

        builder.setIdentity(try identityBuilder.build())

        // Profile

        let profileBuilder = StorageServiceProtoContactRecordProfile.builder()

        if let profileKey = profileKey {
            profileBuilder.setKey(profileKey)
        }

        if let profileName = profileName {
            profileBuilder.setName(profileName)
        }

        builder.setProfile(try profileBuilder.build())

        return try builder.build()
    }

    enum MergeState {
        case resolved(AccountId)
        case needsUpdate(AccountId)
        case invalid
    }

    func mergeWithLocalContact(transaction: SDSAnyWriteTransaction) -> MergeState {
        guard let address = serviceAddress else {
            owsFailDebug("address unexpectedly missing for contact")
            return .invalid
        }

        // Our general merge philosophy is that the latest value on the service
        // is always right. There are some edge cases where this could cause
        // user changes to get blown away, such as if you're changing values
        // simultaneously on two devices or if you force quit the application,
        // your battery dies, etc. before it has had a chance to sync.
        //
        // In general, to try and mitigate these issues, we try and very proactively
        // push any changes up to the storage service as contact information
        // should not be changing very frequently.
        //
        // Should this prove unreliable, we may need to start maintaining time stamps
        // representing the remote and local last update time for every value we sync.
        // For now, we'd like to avoid that as it adds its own set of problems.

        // Mark the user as registered, only registered contacts should exist in the sync'd data.
        let recipient = SignalRecipient.mark(asRegisteredAndGet: address, transaction: transaction)

        var mergeState: MergeState = .resolved(recipient.accountId)

        // Gather some local contact state to do comparisons against.
        let localProfileKey = profileManager.profileKey(for: address, transaction: transaction)
        let localIdentityKey = identityManager.identityKey(for: address, transaction: transaction)
        let localIdentityState = identityManager.verificationState(for: address, transaction: transaction)
        let localIsBlocked = blockingManager.isAddressBlocked(address)
        let localIsWhitelisted = profileManager.isUser(inProfileWhitelist: address, transaction: transaction)

        // If our local profile key record differs from what's on the service, use the service's value.
        if let profileKey = profile?.key, localProfileKey?.keyData != profileKey {
            profileManager.setProfileKeyData(profileKey, for: address, transaction: transaction)

            // We'll immediately schedule a fetch of the new profile, but restore the name
            // if it exists so we we can start displaying it immediately.
            if let profileName = profile?.name {
                profileManager.setProfileName(profileName, for: address, transaction: transaction)
            }

        // If we have a local profile key for this user but the service doesn't mark it as needing update.
        } else if localProfileKey != nil && profile?.hasKey != true {
            mergeState = .needsUpdate(recipient.accountId)
        }

        // If our local identity differs from the service, use the service's value.
        if let identityKey = identity?.key, let identityState = identity?.state?.verificationState,
            localIdentityKey != identityKey || localIdentityState != identityState {
            identityManager.setVerificationState(
                identityState,
                identityKey: identityKey,
                address: address,
                isUserInitiatedChange: false,
                transaction: transaction
            )

        // If we have a local identity for this user but the service doesn't mark it as needing update.
        } else if localIdentityKey != nil && identity?.hasKey != true {
            mergeState = .needsUpdate(recipient.accountId)
        }

        // If our local blocked state differs from the service state, use the service's value.
        if hasBlocked, blocked != localIsBlocked {
            if blocked {
                blockingManager.addBlockedAddress(address, wasLocallyInitiated: false, transaction: transaction)
            } else {
                blockingManager.removeBlockedAddress(address, wasLocallyInitiated: false, transaction: transaction)
            }

        // If the service is missing a blocked state, mark it as needing update.
        } else if !hasBlocked {
            mergeState = .needsUpdate(recipient.accountId)
        }

        // If our local whitelisted state differs from the service state, use the service's value.
        if hasWhitelisted, whitelisted != localIsWhitelisted {
            if whitelisted {
                profileManager.addUser(toProfileWhitelist: address)
            } else {
                profileManager.removeUser(fromProfileWhitelist: address)
            }

        // If the service is missing a whitelisted state, mark it as needing update.
        } else if !hasWhitelisted {
            mergeState = .needsUpdate(recipient.accountId)
        }

        return mergeState
    }
}

// MARK: -

extension StorageServiceProtoContactRecordIdentityState {
    static func from(_ state: OWSVerificationState) -> StorageServiceProtoContactRecordIdentityState {
        switch state {
        case .verified:
            return .verified
        case .default:
            return .default
        case .noLongerVerified:
            return .unverified
        }
    }

    var verificationState: OWSVerificationState {
        switch self {
        case .verified:
            return .verified
        case .default:
            return .default
        case .unverified:
            return .noLongerVerified
        }
    }
}
