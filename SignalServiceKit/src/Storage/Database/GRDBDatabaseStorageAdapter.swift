//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import GRDB

@objc
public class GRDBDatabaseStorageAdapter: NSObject {

    // MARK: - Dependencies

    private var databaseStorage: SDSDatabaseStorage {
        return SDSDatabaseStorage.shared
    }

    private var storageCoordinator: StorageCoordinator {
        return SSKEnvironment.shared.storageCoordinator
    }

    // MARK: -

    static func databaseDirUrl(baseDir: URL) -> URL {
        return baseDir.appendingPathComponent("grdb", isDirectory: true)
    }

    static func databaseFileUrl(baseDir: URL) -> URL {
        let databaseDir = databaseDirUrl(baseDir: baseDir)
        OWSFileSystem.ensureDirectoryExists(databaseDir.path)
        return databaseDir.appendingPathComponent("signal.sqlite", isDirectory: false)
    }

    private let databaseUrl: URL

    private let storage: GRDBStorage

    public var pool: DatabasePool {
        return storage.pool
    }

    init(baseDir: URL) throws {
        databaseUrl = GRDBDatabaseStorageAdapter.databaseFileUrl(baseDir: baseDir)

        try GRDBDatabaseStorageAdapter.ensureDatabaseKeySpecExists(baseDir: baseDir)

        storage = try GRDBStorage(dbURL: databaseUrl, keyspec: GRDBDatabaseStorageAdapter.keyspec)

        super.init()

        AppReadiness.runNowOrWhenAppWillBecomeReady {
            BenchEventStart(title: "GRDB Setup", eventId: "GRDB Setup")
            defer { BenchEventComplete(eventId: "GRDB Setup") }
            do {
                try self.setup()
                try self.setupUIDatabase()
            } catch {
                owsFail("unable to setup database: \(error)")
            }
        }
    }

    func newDatabaseQueue() -> GRDBDatabaseQueue {
        return GRDBDatabaseQueue(storageAdapter: self)
    }

    public func add(function: DatabaseFunction) {
        pool.add(function: function)
    }

    static let tables: [SDSTableMetadata] = [
        // Models
        TSThread.table,
        TSInteraction.table,
        StickerPack.table,
        InstalledSticker.table,
        KnownStickerPack.table,
        TSAttachment.table,
        SSKJobRecord.table,
        OWSMessageContentJob.table,
        OWSRecipientIdentity.table,
        ExperienceUpgrade.table,
        OWSDisappearingMessagesConfiguration.table,
        SignalRecipient.table,
        SignalAccount.table,
        OWSUserProfile.table,
        TSRecipientReadReceipt.table,
        OWSLinkedDeviceReadReceipt.table,
        OWSDevice.table,
        OWSContactQuery.table,
        TestModel.table,
        OWSReaction.table
        // NOTE: We don't include OWSMessageDecryptJob,
        // since we should never use it with GRDB.
    ]

    // MARK: - Database Snapshot

    private var latestSnapshot: DatabaseSnapshot! {
        return uiDatabaseObserver!.latestSnapshot
    }

    @objc
    public private(set) var uiDatabaseObserver: UIDatabaseObserver?

    @objc
    public private(set) var conversationListDatabaseObserver: ConversationListDatabaseObserver?

    @objc
    public private(set) var conversationViewDatabaseObserver: ConversationViewDatabaseObserver?

    @objc
    public private(set) var mediaGalleryDatabaseObserver: MediaGalleryDatabaseObserver?

    @objc
    public private(set) var genericDatabaseObserver: GRDBGenericDatabaseObserver?

    @objc
    public func setupUIDatabase() throws {
        // UIDatabaseObserver is a general purpose observer, whose delegates
        // are notified when things change, but are not given any specific details
        // about the changes.
        let uiDatabaseObserver = try UIDatabaseObserver(pool: pool)
        self.uiDatabaseObserver = uiDatabaseObserver

        // ConversationListDatabaseObserver is built on top of UIDatabaseObserver
        // but includes the details necessary for rendering collection view
        // batch updates.
        let conversationListDatabaseObserver = ConversationListDatabaseObserver()
        self.conversationListDatabaseObserver = conversationListDatabaseObserver
        uiDatabaseObserver.appendSnapshotDelegate(conversationListDatabaseObserver)

        // ConversationViewDatabaseObserver is built on top of UIDatabaseObserver
        // but includes the details necessary for rendering collection view
        // batch updates.
        let conversationViewDatabaseObserver = ConversationViewDatabaseObserver()
        self.conversationViewDatabaseObserver = conversationViewDatabaseObserver
        uiDatabaseObserver.appendSnapshotDelegate(conversationViewDatabaseObserver)

        // MediaGalleryDatabaseObserver is built on top of UIDatabaseObserver
        // but includes the details necessary for rendering collection view
        // batch updates.
        let mediaGalleryDatabaseObserver = MediaGalleryDatabaseObserver()
        self.mediaGalleryDatabaseObserver = mediaGalleryDatabaseObserver
        uiDatabaseObserver.appendSnapshotDelegate(mediaGalleryDatabaseObserver)

        let genericDatabaseObserver = GRDBGenericDatabaseObserver()
        self.genericDatabaseObserver = genericDatabaseObserver
        uiDatabaseObserver.appendSnapshotDelegate(genericDatabaseObserver)

        try pool.write { db in
            db.add(transactionObserver: uiDatabaseObserver, extent: Database.TransactionObservationExtent.observerLifetime)
        }

        SDSDatabaseStorage.shared.observation.set(grdbStorage: self)
    }

    func testing_tearDownUIDatabase() {
        // UIDatabaseObserver is a general purpose observer, whose delegates
        // are notified when things change, but are not given any specific details
        // about the changes.
        self.uiDatabaseObserver = nil
        self.conversationListDatabaseObserver = nil
        self.conversationViewDatabaseObserver = nil
        self.mediaGalleryDatabaseObserver = nil
        self.genericDatabaseObserver = nil
    }

    func setup() throws {
        GRDBMediaGalleryFinder.setup(storage: self)
    }

    // MARK: -

    private static let keyServiceName: String = "GRDBKeyChainService"
    private static let keyName: String = "GRDBDatabaseCipherKeySpec"
    private static var keyspec: GRDBKeySpecSource {
        return GRDBKeySpecSource(keyServiceName: keyServiceName, keyName: keyName)
    }

    @objc
    public static var isKeyAccessible: Bool {
        do {
            return try keyspec.fetchString().count > 0
        } catch {
            owsFailDebug("Key not accessible: \(error)")
            return false
        }
    }

    @objc
    public static func ensureDatabaseKeySpecExists(baseDir: URL) throws {

        do {
            _ = try keyspec.fetchString()
            // Key exists and is valid.
            return
        } catch {
            Logger.warn("Key not accessible: \(error)")
        }

        // Because we use kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        // the keychain will be inaccessible after device restart until
        // device is unlocked for the first time.  If the app receives
        // a push notification, we won't be able to access the keychain to
        // process that notification, so we should just terminate by throwing
        // an uncaught exception.
        var errorDescription = "CipherKeySpec inaccessible. New install, migration or no unlock since device restart?"
        if CurrentAppContext().isMainApp {
            let applicationState = CurrentAppContext().reportedApplicationState
            errorDescription += ", ApplicationState: \(NSStringForUIApplicationState(applicationState))"
        }
        Logger.error(errorDescription)
        Logger.flush()

        if CurrentAppContext().isMainApp {
            if CurrentAppContext().isInBackground() {
                // Rather than crash here, we should have already detected the situation earlier
                // and exited gracefully (in the app delegate) using isDatabasePasswordAccessible.
                // This is a last ditch effort to avoid blowing away the user's database.
                throw OWSAssertionError(errorDescription)
            }
        } else {
            throw OWSAssertionError("CipherKeySpec inaccessible; not main app.")
        }

        // At this point, either:
        //
        // * This is a new install so there's no existing password to retrieve.
        // * The keychain has become corrupt.
        // * We are about to do a ydb-to-grdb migration.
        let databaseUrl = GRDBDatabaseStorageAdapter.databaseFileUrl(baseDir: baseDir)
        let doesDBExist = FileManager.default.fileExists(atPath: databaseUrl.path)
        if doesDBExist {
            owsFail("Could not load database metadata")
        }

        keyspec.generateAndStore()
    }

    @objc
    public static func resetAllStorage(baseDir: URL) {
        Logger.info("")

        // This might be redundant but in the spirit of thoroughness...

        GRDBDatabaseStorageAdapter.removeAllFiles(baseDir: baseDir)

        deleteDBKeys()

        if (CurrentAppContext().isMainApp) {
            TSAttachmentStream.deleteAttachmentsFromDisk()
        }

        // TODO: Delete Profiles on Disk?
    }

    private static func deleteDBKeys() {
        do {
            try keyspec.clear()
        } catch {
            owsFailDebug("Could not clear keychain: \(error)")
        }
    }
}

// MARK: -

extension GRDBDatabaseStorageAdapter: SDSDatabaseStorageAdapter {
    private func assertCanRead() {
        if !databaseStorage.canReadFromGrdb {
            Logger.error("storageMode: \(FeatureFlags.storageModeDescription).")
            Logger.error(
                "StorageCoordinatorState: \(NSStringFromStorageCoordinatorState(storageCoordinator.state)).")
            Logger.error(
                "dataStoreForUI: \(NSStringForDataStore(StorageCoordinator.dataStoreForUI)).")

            switch FeatureFlags.storageModeStrictness {
            case .fail:
                owsFail("Unexpected GRDB read.")
            case .failDebug:
                owsFailDebug("Unexpected GRDB read.")
            case .log:
                Logger.error("Unexpected GRDB read.")
            }
        }
    }

    // TODO readThrows/writeThrows flavors
    public func uiReadThrows(block: @escaping (GRDBReadTransaction) throws -> Void) rethrows {
        assertCanRead()
        AssertIsOnMainThread()
        try latestSnapshot.read { database in
            try autoreleasepool {
                try block(GRDBReadTransaction(database: database))
            }
        }
    }

    public func readThrows<T>(block: @escaping (GRDBReadTransaction) throws -> T) throws -> T {
        assertCanRead()
        AssertIsOnMainThread()
        return try pool.read { database in
            try autoreleasepool {
                return try block(GRDBReadTransaction(database: database))
            }
        }
    }

    @objc
    public func uiRead(block: @escaping (GRDBReadTransaction) -> Void) throws {
        assertCanRead()
        AssertIsOnMainThread()
        latestSnapshot.read { database in
            autoreleasepool {
                block(GRDBReadTransaction(database: database))
            }
        }
    }

    @objc
    public func read(block: @escaping (GRDBReadTransaction) -> Void) throws {
        assertCanRead()
        try pool.read { database in
            autoreleasepool {
                block(GRDBReadTransaction(database: database))
            }
        }
    }

    @objc
    public func write(block: @escaping (GRDBWriteTransaction) -> Void) throws {
        if !databaseStorage.canWriteToGrdb {
            Logger.error("storageMode: \(FeatureFlags.storageModeDescription).")
            Logger.error(
                "StorageCoordinatorState: \(NSStringFromStorageCoordinatorState(storageCoordinator.state)).")
            Logger.error(
                "dataStoreForUI: \(NSStringForDataStore(StorageCoordinator.dataStoreForUI)).")

            switch FeatureFlags.storageModeStrictness {
            case .fail:
                owsFail("Unexpected GRDB write.")
            case .failDebug:
                owsFailDebug("Unexpected GRDB write.")
            case .log:
                Logger.error("Unexpected GRDB write.")
            }
        }

        var transaction: GRDBWriteTransaction!
        try pool.write { database in
            autoreleasepool {
                transaction = GRDBWriteTransaction(database: database)
                block(transaction)
            }
        }
        for (queue, block) in transaction.completions {
            queue.async(execute: block)
        }
    }
}

// MARK: -

private struct GRDBStorage {

    let pool: DatabasePool

    private let dbURL: URL
    private let configuration: Configuration

    // "Busy Timeout" is a thread local so that we can temporarily
    // use a short timeout for checkpoints without interfering with
    // other threads' database usage.
    private static let maxBusyTimeoutMsKey: String = "maxBusyTimeoutMsKey"
    private static var maxBusyTimeoutMs: UInt? {
        get {
            guard let value = Thread.current.threadDictionary[maxBusyTimeoutMsKey] as? UInt else {
                return nil
            }
            return value
        }
        set {
            Thread.current.threadDictionary[maxBusyTimeoutMsKey] = newValue
        }
    }

    fileprivate static func useShortBusyTimeout() {
        maxBusyTimeoutMs = 50
    }
    fileprivate static func useInfiniteBusyTimeout() {
        maxBusyTimeoutMs = nil
    }

    init(dbURL: URL, keyspec: GRDBKeySpecSource) throws {
        self.dbURL = dbURL

        var configuration = Configuration()
        configuration.readonly = false
        configuration.foreignKeysEnabled = true // Default is already true
        configuration.trace = { logString in
            if SDSDatabaseStorage.shouldLogDBQueries {
                func filter(_ input: String) -> String {
                    var result = input

                    while let matchRange = result.range(of: "x'[0-9a-f\n]*'", options: .regularExpression) {
                        let charCount = input.distance(from: matchRange.lowerBound, to: matchRange.upperBound)
                        let byteCount = Int64(charCount) / 2
                        let formattedByteCount = ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .memory)
                        result = result.replacingCharacters(in: matchRange, with: "x'<\(formattedByteCount)>'")
                    }

                    return result
                }
                Logger.info(filter(logString))
            }
        }
        configuration.label = "Modern (GRDB) Storage"      // Useful when your app opens multiple databases
        configuration.maximumReaderCount = 10   // The default is 5
        configuration.busyMode = .callback({ (retryCount: Int) -> Bool in
            // sleep N milliseconds
            let millis = 25
            usleep(useconds_t(millis * 1000))

            Logger.verbose("retryCount: \(retryCount)")
            let accumulatedWaitMs = millis * (retryCount + 1)
            if accumulatedWaitMs > 0, (accumulatedWaitMs % 250) == 0 {
                Logger.warn("Database busy for \(accumulatedWaitMs)ms")
            }

            if let maxBusyTimeoutMs = GRDBStorage.maxBusyTimeoutMs,
                accumulatedWaitMs > maxBusyTimeoutMs {
                Logger.warn("Aborting busy retry.")
                return false
            }

            return true
        })
        configuration.prepareDatabase = { (db: Database) in
            let keyspec = try keyspec.fetchString()
            try db.execute(sql: "PRAGMA key = \"\(keyspec)\"")
            try db.execute(sql: "PRAGMA cipher_plaintext_header_size = 32")
        }
        configuration.defaultTransactionKind = .immediate
        self.configuration = configuration

        pool = try DatabasePool(path: dbURL.path, configuration: configuration)
        Logger.debug("dbURL: \(dbURL)")

        OWSFileSystem.protectFileOrFolder(atPath: dbURL.path)
    }
}

// MARK: -

private struct GRDBKeySpecSource {
    // 256 bit key + 128 bit salt
    private let kSQLCipherKeySpecLength: UInt = 48

    let keyServiceName: String
    let keyName: String

    func fetchString() throws -> String {
        // Use a raw key spec, where the 96 hexadecimal digits are provided
        // (i.e. 64 hex for the 256 bit key, followed by 32 hex for the 128 bit salt)
        // using explicit BLOB syntax, e.g.:
        //
        // x'98483C6EB40B6C31A448C22A66DED3B5E5E8D5119CAC8327B655C8B5C483648101010101010101010101010101010101'
        let data = try fetchData()

        guard data.count == kSQLCipherKeySpecLength else {
            owsFail("unexpected keyspec length")
        }

        let passphrase = "x'\(data.hexadecimalString)'"
        return passphrase
    }

    func fetchData() throws -> Data {
        return try CurrentAppContext().keychainStorage().data(forService: keyServiceName, key: keyName)
    }

    func clear() throws {
        Logger.info("")

        try CurrentAppContext().keychainStorage().remove(service: keyServiceName, key: keyName)
    }

    func generateAndStore() {
        Logger.info("")

        do {
            let keyData = Randomness.generateRandomBytes(Int32(kSQLCipherKeySpecLength))
            try store(data: keyData)
        } catch {
            owsFail("Could not generate key for GRDB: \(error)")
        }
    }

    func store(data: Data) throws {
        guard data.count == kSQLCipherKeySpecLength else {
            owsFail("unexpected keyspec length")
        }
        try CurrentAppContext().keychainStorage().set(data: data, service: keyServiceName, key: keyName)
    }
}

// MARK: -

extension GRDBDatabaseStorageAdapter {
    var databaseFilePath: String {
        return databaseUrl.path
    }

    var databaseWALFilePath: String {
        return databaseUrl.path + "-wal"
    }

    var databaseSHMFilePath: String {
        return databaseUrl.path + "-shm"
    }

    static func removeAllFiles(baseDir: URL) {
        let databaseUrl = GRDBDatabaseStorageAdapter.databaseFileUrl(baseDir: baseDir)
        OWSFileSystem.deleteFileIfExists(databaseUrl.path)
        OWSFileSystem.deleteFileIfExists(databaseUrl.path + "-wal")
        OWSFileSystem.deleteFileIfExists(databaseUrl.path + "-shm")
    }
}

// MARK: - Reporting

extension GRDBDatabaseStorageAdapter {
    var databaseFileSize: UInt64 {
        guard let fileSize = OWSFileSystem.fileSize(ofPath: databaseFilePath) else {
            owsFailDebug("Could not determine file size.")
            return 0
        }
        return fileSize.uint64Value
    }

    var databaseWALFileSize: UInt64 {
        guard let fileSize = OWSFileSystem.fileSize(ofPath: databaseWALFilePath) else {
            owsFailDebug("Could not determine file size.")
            return 0
        }
        return fileSize.uint64Value
    }

    var databaseSHMFileSize: UInt64 {
        guard let fileSize = OWSFileSystem.fileSize(ofPath: databaseSHMFilePath) else {
            owsFailDebug("Could not determine file size.")
            return 0
        }
        return fileSize.uint64Value
    }
}

// MARK: - Checkpoints

public struct GrdbTruncationResult {
    let walSizePages: Int32
    let pagesCheckpointed: Int32
}

extension GRDBDatabaseStorageAdapter {
    @objc
    public func syncTruncatingCheckpoint() throws {
        Logger.info("running truncating checkpoint.")

        SDSDatabaseStorage.shared.logFileSizes()

        let result = try GRDBDatabaseStorageAdapter.checkpoint(pool: pool, mode: .truncate)

        Logger.info("walSizePages: \(result.walSizePages), pagesCheckpointed: \(result.pagesCheckpointed)")

        SDSDatabaseStorage.shared.logFileSizes()
    }

    public static func checkpoint(pool: DatabasePool, mode: Database.CheckpointMode) throws -> GrdbTruncationResult {

        // Use a short busy timeout when checkpointing the WAL.
        // Another process may be active; we don't want to block for long.
        //
        // NOTE: This isn't necessary for .passive checkpoints; they never
        //       block.
        defer {
            // Restore the default busy behavior.
            GRDBStorage.useInfiniteBusyTimeout()
        }
        GRDBStorage.useShortBusyTimeout()

        var walSizePages: Int32 = 0
        var pagesCheckpointed: Int32 = 0
        try Bench(title: "Slow checkpoint: \(mode)", logIfLongerThan: 0.01, logInProduction: true) {
            try pool.writeWithoutTransaction { db in
                let code = sqlite3_wal_checkpoint_v2(db.sqliteConnection, nil, mode.rawValue, &walSizePages, &pagesCheckpointed)
                switch code {
                case SQLITE_OK:
                    if mode != .passive {
                        Logger.info("Checkpoint \(mode) succeeded.")
                    }
                    break
                case SQLITE_BUSY:
                    // Busy is not an error.
                    Logger.info("Checkpoint \(mode) failed due to busy.")
                    break
                default:
                    throw OWSAssertionError("checkpoint sql error with code: \(code)")
                }
            }
        }
        return GrdbTruncationResult(walSizePages: walSizePages, pagesCheckpointed: pagesCheckpointed)
    }
}

// MARK: -

public extension Error {
    var grdbErrorForLogging: Error {
        // If not a GRDB error, return unmodified.
        guard let grdbError = self as? GRDB.DatabaseError else {
            return self
        }
        // DatabaseError.description includes the arguments.
        Logger.verbose("grdbError: \(grdbError))")
        // DatabaseError.description does not include the extendedResultCode.
        Logger.verbose("resultCode: \(grdbError.resultCode), extendedResultCode: \(grdbError.extendedResultCode), message: \(String(describing: grdbError.message)), sql: \(String(describing: grdbError.sql))")
        let error = GRDB.DatabaseError(resultCode: grdbError.extendedResultCode,
                                       message: grdbError.message,
                                       sql: nil,
                                       arguments: nil)
        return error
    }
}
