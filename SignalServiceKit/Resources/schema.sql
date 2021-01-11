CREATE
    TABLE
        keyvalue (
            KEY TEXT NOT NULL
            ,collection TEXT NOT NULL
            ,VALUE BLOB NOT NULL
            ,PRIMARY KEY (
                KEY
                ,collection
            )
        )
;

CREATE
    TABLE
        IF NOT EXISTS "model_TSThread" (
            "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL
            ,"recordType" INTEGER NOT NULL
            ,"uniqueId" TEXT NOT NULL UNIQUE
                ON CONFLICT FAIL
            ,"conversationColorName" TEXT NOT NULL
            ,"creationDate" DOUBLE
            ,"isArchived" INTEGER NOT NULL
            ,"lastInteractionRowId" INTEGER NOT NULL
            ,"messageDraft" TEXT
            ,"mutedUntilDate" DOUBLE
            ,"shouldThreadBeVisible" INTEGER NOT NULL
            ,"contactPhoneNumber" TEXT
            ,"contactUUID" TEXT
            ,"groupModel" BLOB
            ,"hasDismissedOffers" INTEGER
        )
;

CREATE
    INDEX "index_model_TSThread_on_uniqueId"
        ON "model_TSThread"("uniqueId"
)
;

CREATE
    TABLE
        IF NOT EXISTS "model_TSInteraction" (
            "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL
            ,"recordType" INTEGER NOT NULL
            ,"uniqueId" TEXT NOT NULL UNIQUE
                ON CONFLICT FAIL
            ,"receivedAtTimestamp" INTEGER NOT NULL
            ,"timestamp" INTEGER NOT NULL
            ,"uniqueThreadId" TEXT NOT NULL
            ,"attachmentIds" BLOB
            ,"authorId" TEXT
            ,"authorPhoneNumber" TEXT
            ,"authorUUID" TEXT
            ,"body" TEXT
            ,"callType" INTEGER
            ,"configurationDurationSeconds" INTEGER
            ,"configurationIsEnabled" INTEGER
            ,"contactShare" BLOB
            ,"createdByRemoteName" TEXT
            ,"createdInExistingGroup" INTEGER
            ,"customMessage" TEXT
            ,"envelopeData" BLOB
            ,"errorType" INTEGER
            ,"expireStartedAt" INTEGER
            ,"expiresAt" INTEGER
            ,"expiresInSeconds" INTEGER
            ,"groupMetaMessage" INTEGER
            ,"hasLegacyMessageState" INTEGER
            ,"hasSyncedTranscript" INTEGER
            ,"isFromLinkedDevice" INTEGER
            ,"isLocalChange" INTEGER
            ,"isViewOnceComplete" INTEGER
            ,"isViewOnceMessage" INTEGER
            ,"isVoiceMessage" INTEGER
            ,"legacyMessageState" INTEGER
            ,"legacyWasDelivered" INTEGER
            ,"linkPreview" BLOB
            ,"messageId" TEXT
            ,"messageSticker" BLOB
            ,"messageType" INTEGER
            ,"mostRecentFailureText" TEXT
            ,"preKeyBundle" BLOB
            ,"protocolVersion" INTEGER
            ,"quotedMessage" BLOB
            ,"read" INTEGER
            ,"recipientAddress" BLOB
            ,"recipientAddressStates" BLOB
            ,"sender" BLOB
            ,"serverTimestamp" INTEGER
            ,"sourceDeviceId" INTEGER
            ,"storedMessageState" INTEGER
            ,"storedShouldStartExpireTimer" INTEGER
            ,"unregisteredAddress" BLOB
            ,"verificationState" INTEGER
            ,"wasReceivedByUD" INTEGER
        )
;

CREATE
    INDEX "index_model_TSInteraction_on_uniqueId"
        ON "model_TSInteraction"("uniqueId"
)
;

CREATE
    TABLE
        IF NOT EXISTS "model_StickerPack" (
            "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL
            ,"recordType" INTEGER NOT NULL
            ,"uniqueId" TEXT NOT NULL UNIQUE
                ON CONFLICT FAIL
            ,"author" TEXT
            ,"cover" BLOB NOT NULL
            ,"dateCreated" DOUBLE NOT NULL
            ,"info" BLOB NOT NULL
            ,"isInstalled" INTEGER NOT NULL
            ,"items" BLOB NOT NULL
            ,"title" TEXT
        )
;

CREATE
    INDEX "index_model_StickerPack_on_uniqueId"
        ON "model_StickerPack"("uniqueId"
)
;

CREATE
    TABLE
        IF NOT EXISTS "model_InstalledSticker" (
            "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL
            ,"recordType" INTEGER NOT NULL
            ,"uniqueId" TEXT NOT NULL UNIQUE
                ON CONFLICT FAIL
            ,"emojiString" TEXT
            ,"info" BLOB NOT NULL
        )
;

CREATE
    INDEX "index_model_InstalledSticker_on_uniqueId"
        ON "model_InstalledSticker"("uniqueId"
)
;

CREATE
    TABLE
        IF NOT EXISTS "model_KnownStickerPack" (
            "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL
            ,"recordType" INTEGER NOT NULL
            ,"uniqueId" TEXT NOT NULL UNIQUE
                ON CONFLICT FAIL
            ,"dateCreated" DOUBLE NOT NULL
            ,"info" BLOB NOT NULL
            ,"referenceCount" INTEGER NOT NULL
        )
;

CREATE
    INDEX "index_model_KnownStickerPack_on_uniqueId"
        ON "model_KnownStickerPack"("uniqueId"
)
;

CREATE
    TABLE
        IF NOT EXISTS "model_TSAttachment" (
            "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL
            ,"recordType" INTEGER NOT NULL
            ,"uniqueId" TEXT NOT NULL UNIQUE
                ON CONFLICT FAIL
            ,"albumMessageId" TEXT
            ,"attachmentType" INTEGER NOT NULL
            ,"blurHash" TEXT
            ,"byteCount" INTEGER NOT NULL
            ,"caption" TEXT
            ,"contentType" TEXT NOT NULL
            ,"encryptionKey" BLOB
            ,"serverId" INTEGER NOT NULL
            ,"sourceFilename" TEXT
            ,"cachedAudioDurationSeconds" DOUBLE
            ,"cachedImageHeight" DOUBLE
            ,"cachedImageWidth" DOUBLE
            ,"creationTimestamp" DOUBLE
            ,"digest" BLOB
            ,"isUploaded" INTEGER
            ,"isValidImageCached" INTEGER
            ,"isValidVideoCached" INTEGER
            ,"lazyRestoreFragmentId" TEXT
            ,"localRelativeFilePath" TEXT
            ,"mediaSize" BLOB
            ,"pointerType" INTEGER
            ,"state" INTEGER
        )
;

CREATE
    INDEX "index_model_TSAttachment_on_uniqueId"
        ON "model_TSAttachment"("uniqueId"
)
;

CREATE
    TABLE
        IF NOT EXISTS "model_SSKJobRecord" (
            "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL
            ,"recordType" INTEGER NOT NULL
            ,"uniqueId" TEXT NOT NULL UNIQUE
                ON CONFLICT FAIL
            ,"failureCount" INTEGER NOT NULL
            ,"label" TEXT NOT NULL
            ,"status" INTEGER NOT NULL
            ,"attachmentIdMap" BLOB
            ,"contactThreadId" TEXT
            ,"envelopeData" BLOB
            ,"invisibleMessage" BLOB
            ,"messageId" TEXT
            ,"removeMessageAfterSending" INTEGER
            ,"threadId" TEXT
            ,"attachmentId" TEXT
        )
;

CREATE
    INDEX "index_model_SSKJobRecord_on_uniqueId"
        ON "model_SSKJobRecord"("uniqueId"
)
;

CREATE
    TABLE
        IF NOT EXISTS "model_OWSMessageContentJob" (
            "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL
            ,"recordType" INTEGER NOT NULL
            ,"uniqueId" TEXT NOT NULL UNIQUE
                ON CONFLICT FAIL
            ,"createdAt" DOUBLE NOT NULL
            ,"envelopeData" BLOB NOT NULL
            ,"plaintextData" BLOB
            ,"wasReceivedByUD" INTEGER NOT NULL
        )
;

CREATE
    INDEX "index_model_OWSMessageContentJob_on_uniqueId"
        ON "model_OWSMessageContentJob"("uniqueId"
)
;

CREATE
    TABLE
        IF NOT EXISTS "model_OWSRecipientIdentity" (
            "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL
            ,"recordType" INTEGER NOT NULL
            ,"uniqueId" TEXT NOT NULL UNIQUE
                ON CONFLICT FAIL
            ,"accountId" TEXT NOT NULL
            ,"createdAt" DOUBLE NOT NULL
            ,"identityKey" BLOB NOT NULL
            ,"isFirstKnownKey" INTEGER NOT NULL
            ,"verificationState" INTEGER NOT NULL
        )
;

CREATE
    INDEX "index_model_OWSRecipientIdentity_on_uniqueId"
        ON "model_OWSRecipientIdentity"("uniqueId"
)
;

CREATE
    TABLE
        IF NOT EXISTS "model_ExperienceUpgrade" (
            "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL
            ,"recordType" INTEGER NOT NULL
            ,"uniqueId" TEXT NOT NULL UNIQUE
                ON CONFLICT FAIL
        )
;

CREATE
    INDEX "index_model_ExperienceUpgrade_on_uniqueId"
        ON "model_ExperienceUpgrade"("uniqueId"
)
;

CREATE
    TABLE
        IF NOT EXISTS "model_OWSDisappearingMessagesConfiguration" (
            "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL
            ,"recordType" INTEGER NOT NULL
            ,"uniqueId" TEXT NOT NULL UNIQUE
                ON CONFLICT FAIL
            ,"durationSeconds" INTEGER NOT NULL
            ,"enabled" INTEGER NOT NULL
        )
;

CREATE
    INDEX "index_model_OWSDisappearingMessagesConfiguration_on_uniqueId"
        ON "model_OWSDisappearingMessagesConfiguration"("uniqueId"
)
;

CREATE
    TABLE
        IF NOT EXISTS "model_SignalRecipient" (
            "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL
            ,"recordType" INTEGER NOT NULL
            ,"uniqueId" TEXT NOT NULL UNIQUE
                ON CONFLICT FAIL
            ,"devices" BLOB NOT NULL
            ,"recipientPhoneNumber" TEXT
            ,"recipientUUID" TEXT
        )
;

CREATE
    INDEX "index_model_SignalRecipient_on_uniqueId"
        ON "model_SignalRecipient"("uniqueId"
)
;

CREATE
    TABLE
        IF NOT EXISTS "model_OWSUserProfile" (
            "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL
            ,"recordType" INTEGER NOT NULL
            ,"uniqueId" TEXT NOT NULL UNIQUE
                ON CONFLICT FAIL
            ,"avatarFileName" TEXT
            ,"avatarUrlPath" TEXT
            ,"profileKey" BLOB
            ,"profileName" TEXT
            ,"recipientPhoneNumber" TEXT
            ,"recipientUUID" TEXT
            ,"username" TEXT
        )
;

CREATE
    INDEX "index_model_OWSUserProfile_on_uniqueId"
        ON "model_OWSUserProfile"("uniqueId"
)
;

CREATE
    TABLE
        IF NOT EXISTS "model_TSRecipientReadReceipt" (
            "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL
            ,"recordType" INTEGER NOT NULL
            ,"uniqueId" TEXT NOT NULL UNIQUE
                ON CONFLICT FAIL
            ,"recipientMap" BLOB NOT NULL
            ,"sentTimestamp" INTEGER NOT NULL
        )
;

CREATE
    INDEX "index_model_TSRecipientReadReceipt_on_uniqueId"
        ON "model_TSRecipientReadReceipt"("uniqueId"
)
;

CREATE
    TABLE
        IF NOT EXISTS "model_OWSLinkedDeviceReadReceipt" (
            "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL
            ,"recordType" INTEGER NOT NULL
            ,"uniqueId" TEXT NOT NULL UNIQUE
                ON CONFLICT FAIL
            ,"messageIdTimestamp" INTEGER NOT NULL
            ,"readTimestamp" INTEGER NOT NULL
            ,"senderPhoneNumber" TEXT
            ,"senderUUID" TEXT
        )
;

CREATE
    INDEX "index_model_OWSLinkedDeviceReadReceipt_on_uniqueId"
        ON "model_OWSLinkedDeviceReadReceipt"("uniqueId"
)
;

CREATE
    TABLE
        IF NOT EXISTS "model_OWSDevice" (
            "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL
            ,"recordType" INTEGER NOT NULL
            ,"uniqueId" TEXT NOT NULL UNIQUE
                ON CONFLICT FAIL
            ,"createdAt" DOUBLE NOT NULL
            ,"deviceId" INTEGER NOT NULL
            ,"lastSeenAt" DOUBLE NOT NULL
            ,"name" TEXT
        )
;

CREATE
    INDEX "index_model_OWSDevice_on_uniqueId"
        ON "model_OWSDevice"("uniqueId"
)
;

CREATE
    TABLE
        IF NOT EXISTS "model_OWSContactQuery" (
            "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL
            ,"recordType" INTEGER NOT NULL
            ,"uniqueId" TEXT NOT NULL UNIQUE
                ON CONFLICT FAIL
            ,"lastQueried" DOUBLE NOT NULL
            ,"nonce" BLOB NOT NULL
        )
;

CREATE
    INDEX "index_model_OWSContactQuery_on_uniqueId"
        ON "model_OWSContactQuery"("uniqueId"
)
;

CREATE
    TABLE
        IF NOT EXISTS "model_TestModel" (
            "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL
            ,"recordType" INTEGER NOT NULL
            ,"uniqueId" TEXT NOT NULL UNIQUE
                ON CONFLICT FAIL
            ,"dateValue" DOUBLE
            ,"doubleValue" DOUBLE NOT NULL
            ,"floatValue" DOUBLE NOT NULL
            ,"int64Value" INTEGER NOT NULL
            ,"nsIntegerValue" INTEGER NOT NULL
            ,"nsNumberValueUsingInt64" INTEGER
            ,"nsNumberValueUsingUInt64" INTEGER
            ,"nsuIntegerValue" INTEGER NOT NULL
            ,"uint64Value" INTEGER NOT NULL
        )
;

CREATE
    INDEX "index_model_TestModel_on_uniqueId"
        ON "model_TestModel"("uniqueId"
)
;

CREATE
    INDEX "index_interactions_on_threadUniqueId_and_id"
        ON "model_TSInteraction"("uniqueThreadId"
    ,"id"
)
;

CREATE
    INDEX "index_jobs_on_label_and_id"
        ON "model_SSKJobRecord"("label"
    ,"id"
)
;

CREATE
    INDEX "index_jobs_on_status_and_label_and_id"
        ON "model_SSKJobRecord"("label"
    ,"status"
    ,"id"
)
;

CREATE
    INDEX "index_interactions_on_view_once"
        ON "model_TSInteraction"("isViewOnceMessage"
    ,"isViewOnceComplete"
)
;

CREATE
    INDEX "index_key_value_store_on_collection_and_key"
        ON "keyvalue"("collection"
    ,"key"
)
;

CREATE
    INDEX "index_interactions_on_recordType_and_threadUniqueId_and_errorType"
        ON "model_TSInteraction"("recordType"
    ,"uniqueThreadId"
    ,"errorType"
)
;

CREATE
    INDEX "index_attachments_on_albumMessageId"
        ON "model_TSAttachment"("albumMessageId"
    ,"recordType"
)
;

CREATE
    INDEX "index_interactions_on_uniqueId_and_threadUniqueId"
        ON "model_TSInteraction"("uniqueThreadId"
    ,"uniqueId"
)
;

CREATE
    INDEX "index_thread_on_contactPhoneNumber"
        ON "model_TSThread"("contactPhoneNumber"
)
;

CREATE
    INDEX "index_thread_on_contactUUID"
        ON "model_TSThread"("contactUUID"
)
;

CREATE
    INDEX "index_thread_on_shouldThreadBeVisible"
        ON "model_TSThread"("shouldThreadBeVisible"
    ,"isArchived"
    ,"lastInteractionRowId"
)
;

CREATE
    INDEX "index_user_profiles_on_recipientPhoneNumber"
        ON "model_OWSUserProfile"("recipientPhoneNumber"
)
;

CREATE
    INDEX "index_user_profiles_on_recipientUUID"
        ON "model_OWSUserProfile"("recipientUUID"
)
;

CREATE
    INDEX "index_user_profiles_on_username"
        ON "model_OWSUserProfile"("username"
)
;

CREATE
    INDEX "index_linkedDeviceReadReceipt_on_senderPhoneNumberAndTimestamp"
        ON "model_OWSLinkedDeviceReadReceipt"("senderPhoneNumber"
    ,"messageIdTimestamp"
)
;

CREATE
    INDEX "index_linkedDeviceReadReceipt_on_senderUUIDAndTimestamp"
        ON "model_OWSLinkedDeviceReadReceipt"("senderUUID"
    ,"messageIdTimestamp"
)
;

CREATE
    INDEX "index_interactions_on_timestamp_sourceDeviceId_and_authorUUID"
        ON "model_TSInteraction"("timestamp"
    ,"sourceDeviceId"
    ,"authorUUID"
)
;

CREATE
    INDEX "index_interactions_on_timestamp_sourceDeviceId_and_authorPhoneNumber"
        ON "model_TSInteraction"("timestamp"
    ,"sourceDeviceId"
    ,"authorPhoneNumber"
)
;

CREATE
    INDEX "index_interactions_unread_counts"
        ON "model_TSInteraction"("read"
    ,"uniqueThreadId"
    ,"recordType"
)
;

CREATE
    INDEX "index_interactions_on_expiresInSeconds_and_expiresAt"
        ON "model_TSInteraction"("expiresAt"
    ,"expiresInSeconds"
)
;

CREATE
    INDEX "index_interactions_on_threadUniqueId_storedShouldStartExpireTimer_and_expiresAt"
        ON "model_TSInteraction"("expiresAt"
    ,"expireStartedAt"
    ,"storedShouldStartExpireTimer"
    ,"uniqueThreadId"
)
;

CREATE
    INDEX "index_contact_queries_on_lastQueried"
        ON "model_OWSContactQuery"("lastQueried"
)
;

CREATE
    INDEX "index_attachments_on_lazyRestoreFragmentId"
        ON "model_TSAttachment"("lazyRestoreFragmentId"
)
;

CREATE
    VIRTUAL TABLE
        "signal_grdb_fts"
            USING fts5 (
            collection UNINDEXED
            ,uniqueId UNINDEXED
            ,ftsIndexableContent
            ,tokenize = 'unicode61'
        ) /* signal_grdb_fts(collection,uniqueId,ftsIndexableContent) */
;

CREATE
    TABLE
        IF NOT EXISTS 'signal_grdb_fts_data' (
            id INTEGER PRIMARY KEY
            ,block BLOB
        )
;

CREATE
    TABLE
        IF NOT EXISTS 'signal_grdb_fts_idx' (
            segid
            ,term
            ,pgno
            ,PRIMARY KEY (
                segid
                ,term
            )
        ) WITHOUT ROWID
;

CREATE
    TABLE
        IF NOT EXISTS 'signal_grdb_fts_content' (
            id INTEGER PRIMARY KEY
            ,c0
            ,c1
            ,c2
        )
;

CREATE
    TABLE
        IF NOT EXISTS 'signal_grdb_fts_docsize' (
            id INTEGER PRIMARY KEY
            ,sz BLOB
        )
;

CREATE
    TABLE
        IF NOT EXISTS 'signal_grdb_fts_config' (
            k PRIMARY KEY
            ,v
        ) WITHOUT ROWID
;

CREATE
    TABLE
        IF NOT EXISTS "model_SignalAccount" (
            "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL
            ,"recordType" INTEGER NOT NULL
            ,"uniqueId" TEXT NOT NULL UNIQUE
                ON CONFLICT FAIL
            ,"contact" BLOB
            ,"contactAvatarHash" BLOB
            ,"contactAvatarJpegData" BLOB
            ,"multipleAccountLabelText" TEXT NOT NULL
            ,"recipientPhoneNumber" TEXT
            ,"recipientUUID" TEXT
        )
;

CREATE
    INDEX "index_model_SignalAccount_on_uniqueId"
        ON "model_SignalAccount"("uniqueId"
)
;

CREATE
    INDEX "index_signal_accounts_on_recipientPhoneNumber"
        ON "model_SignalAccount"("recipientPhoneNumber"
)
;

CREATE
    INDEX "index_signal_accounts_on_recipientUUID"
        ON "model_SignalAccount"("recipientUUID"
)
;

CREATE
    TABLE
        IF NOT EXISTS "model_OWSReaction" (
            "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL
            ,"recordType" INTEGER NOT NULL
            ,"uniqueId" TEXT NOT NULL UNIQUE
                ON CONFLICT FAIL
            ,"emoji" TEXT NOT NULL
            ,"reactorE164" TEXT
            ,"reactorUUID" TEXT
            ,"receivedAtTimestamp" INTEGER NOT NULL
            ,"sentAtTimestamp" INTEGER NOT NULL
            ,"uniqueMessageId" TEXT NOT NULL
        )
;

CREATE
    INDEX "index_model_OWSReaction_on_uniqueId"
        ON "model_OWSReaction"("uniqueId"
)
;

CREATE
    INDEX "index_model_OWSReaction_on_uniqueMessageId_and_reactorE164"
        ON "model_OWSReaction"("uniqueMessageId"
    ,"reactorE164"
)
;

CREATE
    INDEX "index_model_OWSReaction_on_uniqueMessageId_and_reactorUUID"
        ON "model_OWSReaction"("uniqueMessageId"
    ,"reactorUUID"
)
;

CREATE
    TABLE
        IF NOT EXISTS "media_gallery_items" (
            "attachmentId" INTEGER NOT NULL UNIQUE
            ,"albumMessageId" INTEGER NOT NULL
            ,"threadId" INTEGER NOT NULL
            ,"originalAlbumOrder" INTEGER NOT NULL
        )
;

CREATE
    INDEX "index_media_gallery_items_for_gallery"
        ON "media_gallery_items"("threadId"
    ,"albumMessageId"
    ,"originalAlbumOrder"
)
;

CREATE
    INDEX "index_media_gallery_items_on_attachmentId"
        ON "media_gallery_items"("attachmentId"
)
;

CREATE
    UNIQUE INDEX "index_signal_recipients_on_recipientPhoneNumber"
        ON "model_SignalRecipient"("recipientPhoneNumber"
)
;

CREATE
    UNIQUE INDEX "index_signal_recipients_on_recipientUUID"
        ON "model_SignalRecipient"("recipientUUID"
)
;

CREATE
    UNIQUE INDEX "index_interactions_on_threadId_read_and_id"
        ON "model_TSInteraction"("uniqueThreadId"
    ,"read"
    ,"id"
)
;
