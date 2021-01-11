//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc(OWSReactionManager)
public class ReactionManager: NSObject {
    static var databaseStorage: SDSDatabaseStorage {
        return .shared
    }

    static var tsAccountManager: TSAccountManager {
        return .sharedInstance()
    }

    public static let emojiSet = ["❤️", "👍", "👎", "😂", "😮", "😢", "😡"]

    @objc(localUserReactedToMessage:emoji:isRemoving:transaction:)
    public class func localUserReacted(to message: TSMessage, emoji: String, isRemoving: Bool, transaction: SDSAnyWriteTransaction) {
        guard FeatureFlags.reactionSend else {
            Logger.info("Not sending reaction, feature disabled")
            return
        }

        assert(emoji.isSingleEmoji)

        Logger.info("Sending reaction: \(emoji) isRemoving: \(isRemoving)")

        guard let localAddress = tsAccountManager.localAddress else {
            return owsFailDebug("missing local address")
        }

        // Though we generally don't parse the expiration timer from
        // reaction messages, older desktop instances will read it
        // from the "unsupported" message resulting in the timer
        // clearing. So we populate it to ensure that does not happen.
        let expiresInSeconds: UInt32
        if let configuration = OWSDisappearingMessagesConfiguration.anyFetch(
            uniqueId: message.uniqueThreadId,
            transaction: transaction
        ), configuration.isEnabled {
            expiresInSeconds = configuration.durationSeconds
        } else {
            expiresInSeconds = 0
        }

        let outgoingMessage = OWSOutgoingReactionMessage(
            thread: message.thread(transaction: transaction),
            message: message,
            emoji: emoji,
            isRemoving: isRemoving,
            expiresInSeconds: expiresInSeconds
        )

        outgoingMessage.previousReaction = message.reaction(for: localAddress, transaction: transaction)

        if isRemoving {
            message.removeReaction(for: localAddress, transaction: transaction)
        } else {
            outgoingMessage.createdReaction = message.recordReaction(
                for: localAddress,
                emoji: emoji,
                sentAtTimestamp: outgoingMessage.timestamp,
                receivedAtTimestamp: outgoingMessage.timestamp,
                transaction: transaction
            )
        }

        SSKEnvironment.shared.messageSenderJobQueue.add(message: outgoingMessage.asPreparer, transaction: transaction)
    }

    @objc
    class func processIncomingReaction(
        _ reaction: SSKProtoDataMessageReaction,
        threadId: String,
        reactor: SignalServiceAddress,
        timestamp: UInt64,
        transaction: SDSAnyWriteTransaction
    ) {
        guard FeatureFlags.reactionReceive else {
            Logger.info("Ignoring incoming reaction, feature disabled")
            return
        }

        guard reaction.emoji.isSingleEmoji else {
            owsFailDebug("Received invalid emoji")
            return
        }

        guard let messageAuthor = reaction.authorAddress else {
            return owsFailDebug("reaction missing author address")
        }

        guard let message = InteractionFinder.findMessage(
            withTimestamp: reaction.timestamp,
            threadId: threadId,
            author: messageAuthor,
            transaction: transaction
        ) else {
            // This is potentially normal. For example, we could've deleted the message locally.
            Logger.info("Received reaction for a message that doesn't exist \(timestamp)")
            return
        }

        // If this is a reaction removal, we want to remove *any* reaction from this author
        // on this message, regardless of the specified emoji.
        if reaction.remove {
            message.removeReaction(for: reactor, transaction: transaction)
        } else {
            let reaction = message.recordReaction(
                for: reactor,
                emoji: reaction.emoji,
                sentAtTimestamp: timestamp,
                receivedAtTimestamp: NSDate.ows_millisecondTimeStamp(),
                transaction: transaction
            )

            // If this is a reaction to a message we sent, notify the user.
            if message is TSOutgoingMessage, !reactor.isLocalAddress {
                guard let thread = TSThread.anyFetch(uniqueId: threadId, transaction: transaction) else {
                    return owsFailDebug("Failed to lookup thread for reaction notification.")
                }

                SSKEnvironment.shared.notificationsManager.notifyUser(for: reaction, in: thread, transaction: transaction)
            }
        }
    }
}
