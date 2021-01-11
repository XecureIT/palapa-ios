//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public protocol SDSDatabaseStorageDelegate {
    var storageCoordinatorState: StorageCoordinatorState { get }
}

// MARK: -

@objc
public class SDSDatabaseStorage: SDSTransactable {

    @objc
    public static var shared: SDSDatabaseStorage {
        return SSKEnvironment.shared.databaseStorage
    }

    private weak var delegate: SDSDatabaseStorageDelegate?

    static public var shouldLogDBQueries: Bool = FeatureFlags.logSQLQueries

    private var hasPendingCrossProcessWrite = false

    private let crossProcess = SDSCrossProcess()

    let observation = SDSDatabaseStorageObservation()

    // MARK: - Initialization / Setup

    @objc
    public var yapPrimaryStorage: OWSPrimaryStorage {
        return yapStorage.storage
    }

    private var _yapStorage: YAPDBStorageAdapter?

    var yapStorage: YAPDBStorageAdapter {
        if let storage = _yapStorage {
            return storage
        } else {
            let storage = createYapStorage()
            _yapStorage = storage
            return storage
        }
    }

    private var _grdbStorage: GRDBDatabaseStorageAdapter?

    @objc
    public var grdbStorage: GRDBDatabaseStorageAdapter {
        if let storage = _grdbStorage {
            return storage
        } else {
            let storage = createGrdbStorage()
            _grdbStorage = storage
            return storage
        }
    }

    @objc
    required init(delegate: SDSDatabaseStorageDelegate) {
        self.delegate = delegate

        super.init()

        addObservers()
    }

    private func addObservers() {
        guard !CurrentAppContext().isRunningTests else {
            return
        }
        guard StorageCoordinator.dataStoreForUI == .grdb else {
            // YDB uses a different mechanism for cross process writes.
            return
        }
        // Cross process writes
        crossProcess.callback = { [weak self] in
            DispatchQueue.main.async {
                self?.handleCrossProcessWrite()
            }
        }
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(didBecomeActive),
                                               name: UIApplication.didBecomeActiveNotification,
                                               object: nil)
    }

    deinit {
        Logger.verbose("")

        NotificationCenter.default.removeObserver(self)
    }

    // GRDB TODO: Remove
    @objc
    public static var shouldUseDisposableGrdb: Bool {
        // We don't need to use a "disposable" database in our tests;
        // TestAppContext ensures that our entire appSharedDataDirectoryPath
        // is disposable in that case.

        if .grdbThrowawayIfMigrating == FeatureFlags.storageMode {
            // .grdbThrowawayIfMigrating allows us to re-test the migration on each launch.
            // It doesn't make sense (and won't work) if there's no YDB database
            // to migrate.
            //
            // Specifically, state persisted in NSUserDefaults won't be "throw away"
            // and this will break the app if we throw away our database.
            return StorageCoordinator.hasYdbFile
        }
        return false
    }

    private class func baseDir() -> URL {
        return URL(fileURLWithPath: CurrentAppContext().appDatabaseBaseDirectoryPath(),
                   isDirectory: true)
    }

    @objc
    public static var grdbDatabaseDirUrl: URL {
        return GRDBDatabaseStorageAdapter.databaseDirUrl(baseDir: baseDir())
    }

    @objc
    public static var grdbDatabaseFileUrl: URL {
        return GRDBDatabaseStorageAdapter.databaseFileUrl(baseDir: baseDir())
    }

    func createGrdbStorage() -> GRDBDatabaseStorageAdapter {
        if !canLoadGrdb {
            Logger.error("storageMode: \(FeatureFlags.storageModeDescription).")
            Logger.error(
                "StorageCoordinatorState: \(storageCoordinatorStateDescription).")
            Logger.error(
                "dataStoreForUI: \(NSStringForDataStore(StorageCoordinator.dataStoreForUI)).")

            switch FeatureFlags.storageModeStrictness {
            case .fail:
                owsFail("Unexpected GRDB load.")
            case .failDebug:
                owsFailDebug("Unexpected GRDB load.")
            case .log:
                Logger.error("Unexpected GRDB load.")
            }
        }

        if FeatureFlags.storageMode == .ydbForAll {
            owsFailDebug("Unexpected storage mode: \(FeatureFlags.storageModeDescription)")
        }
        if StorageCoordinator.dataStoreForUI == .ydb && !CurrentAppContext().isRunningTests {
            owsFailDebug("Unexpected data store.")
        }

        // crash if we can't read the DB.
        do {
            return try Bench(title: "Creating GRDB storage") {
                return try GRDBDatabaseStorageAdapter(baseDir: type(of: self).baseDir())
            }
        } catch {
            owsFail("\(error.grdbErrorForLogging)")
        }
    }

    @objc
    public func deleteGrdbFiles() {
        GRDBDatabaseStorageAdapter.removeAllFiles(baseDir: type(of: self).baseDir())
    }

    @objc
    public func resetAllStorage() {
        OWSStorage.resetAllStorage()
        GRDBDatabaseStorageAdapter.resetAllStorage(baseDir: type(of: self).baseDir())
    }

    func createYapStorage() -> YAPDBStorageAdapter {
        if !canLoadYdb {
            Logger.error("storageMode: \(FeatureFlags.storageModeDescription).")
            Logger.error(
                "StorageCoordinatorState: \(storageCoordinatorStateDescription).")
            Logger.error(
                "dataStoreForUI: \(NSStringForDataStore(StorageCoordinator.dataStoreForUI)).")

            switch FeatureFlags.storageModeStrictness {
            case .fail:
                owsFail("Unexpected YDB load.")
            case .failDebug:
                owsFailDebug("Unexpected YDB load.")
            case .log:
                Logger.error("Unexpected YDB load.")
            }
        }

        return Bench(title: "Creating YDB storage") {
            let yapPrimaryStorage = OWSPrimaryStorage()
            return YAPDBStorageAdapter(storage: yapPrimaryStorage)
        }
    }

    // MARK: -

    @objc
    public func newDatabaseQueue() -> SDSAnyDatabaseQueue {
        var yapDatabaseQueue: YAPDBDatabaseQueue?
        var grdbDatabaseQueue: GRDBDatabaseQueue?

        switch storageCoordinatorState {
        case .YDB:
            yapDatabaseQueue = yapStorage.newDatabaseQueue()
        case .GRDB:
            grdbDatabaseQueue = grdbStorage.newDatabaseQueue()
        case .ydbTests, .grdbTests, .beforeYDBToGRDBMigration, .duringYDBToGRDBMigration:
            yapDatabaseQueue = yapStorage.newDatabaseQueue()
            grdbDatabaseQueue = grdbStorage.newDatabaseQueue()
        }

        return SDSAnyDatabaseQueue(yapDatabaseQueue: yapDatabaseQueue,
                                   grdbDatabaseQueue: grdbDatabaseQueue,
                                   crossProcess: crossProcess)
    }

    // MARK: - Touch

    @objc(touchInteraction:transaction:)
    public func touch(interaction: TSInteraction, transaction: SDSAnyWriteTransaction) {
        switch transaction.writeTransaction {
        case .yapWrite(let yap):
            let uniqueId = interaction.uniqueId
            yap.touchObject(forKey: uniqueId, inCollection: TSInteraction.collection())
        case .grdbWrite(let grdb):
            UIDatabaseObserver.serializedSync {
                guard !UIDatabaseObserver.skipTouchObservations else {
                    return
                }

                if let conversationViewDatabaseObserver = grdbStorage.conversationViewDatabaseObserver {
                    conversationViewDatabaseObserver.didTouch(interaction: interaction, transaction: grdb)
                } else if AppReadiness.isAppReady() {
                    owsFailDebug("conversationViewDatabaseObserver was unexpectedly nil")
                }
                if let genericDatabaseObserver = grdbStorage.genericDatabaseObserver {
                    genericDatabaseObserver.didTouch(interaction: interaction,
                                                     transaction: grdb)
                } else if AppReadiness.isAppReady() {
                    owsFailDebug("genericDatabaseObserver was unexpectedly nil")
                }
                GRDBFullTextSearchFinder.modelWasUpdated(model: interaction, transaction: grdb)
            }
        }
    }

    @objc(touchThread:transaction:)
    public func touch(thread: TSThread, transaction: SDSAnyWriteTransaction) {
        switch transaction.writeTransaction {
        case .yapWrite(let yap):
            yap.touchObject(forKey: thread.uniqueId, inCollection: TSThread.collection())
        case .grdbWrite(let grdb):
            UIDatabaseObserver.serializedSync {
                guard !UIDatabaseObserver.skipTouchObservations else {
                    return
                }

                if let conversationListDatabaseObserver = grdbStorage.conversationListDatabaseObserver {
                    conversationListDatabaseObserver.didTouch(thread: thread, transaction: grdb)
                } else if AppReadiness.isAppReady() {
                    owsFailDebug("conversationListDatabaseObserver was unexpectedly nil")
                }
                if let conversationViewDatabaseObserver = grdbStorage.conversationViewDatabaseObserver {
                    conversationViewDatabaseObserver.didTouch(thread: thread, transaction: grdb)
                } else if AppReadiness.isAppReady() {
                    owsFailDebug("conversationViewDatabaseObserver was unexpectedly nil")
                }
                if let genericDatabaseObserver = grdbStorage.genericDatabaseObserver {
                    genericDatabaseObserver.didTouchThread(transaction: grdb)
                } else if AppReadiness.isAppReady() {
                    owsFailDebug("genericDatabaseObserver was unexpectedly nil")
                }
                GRDBFullTextSearchFinder.modelWasUpdated(model: thread, transaction: grdb)
            }
        }
    }

    // MARK: - Cross Process Notifications

    private func handleCrossProcessWrite() {
        AssertIsOnMainThread()

        Logger.info("")

        guard CurrentAppContext().isMainApp else {
            return
        }

        if CurrentAppContext().isMainAppAndActive {
            // If already active, update immediately.
            postCrossProcessNotification()
        } else {
            // If not active, set flag to update when we become active.
            hasPendingCrossProcessWrite = true
        }
    }

    @objc func didBecomeActive() {
        AssertIsOnMainThread()

        guard hasPendingCrossProcessWrite else {
            return
        }
        hasPendingCrossProcessWrite = false

        postCrossProcessNotification()
    }

    @objc
    public static let didReceiveCrossProcessNotification = Notification.Name("didReceiveCrossProcessNotification")

    private func postCrossProcessNotification() {
        Logger.info("")

        // TODO: The observers of this notification will inevitably do
        //       expensive work.  It'd be nice to only fire this event
        //       if this had any effect, if the state of the database
        //       has changed.
        //
        //       In the meantime, most (all?) cross process write notifications
        //       will be delivered to the main app while it is inactive. By
        //       de-bouncing notifications while inactive and only updating
        //       once when we become active, we should be able to effectively
        //       skip most of the perf cost.
        NotificationCenter.default.postNotificationNameAsync(SDSDatabaseStorage.didReceiveCrossProcessNotification, object: nil)
    }

    // MARK: - Generic Observation

    @objc(addDatabaseStorageObserver:)
    public func add(databaseStorageObserver: SDSDatabaseStorageObserver) {
        observation.add(databaseStorageObserver: databaseStorageObserver)
    }

    // MARK: - SDSTransactable

    @objc
    public func uiRead(block: @escaping (SDSAnyReadTransaction) -> Void) {
        switch dataStoreForReads {
        case .grdb:
            do {
                try grdbStorage.uiRead { transaction in
                    block(transaction.asAnyRead)
                }
            } catch {
                owsFail("error: \(error.grdbErrorForLogging)")
            }
        case .ydb:
            yapStorage.uiRead { transaction in
                block(transaction.asAnyRead)
            }
        }
    }

    @objc
    public override func read(block: @escaping (SDSAnyReadTransaction) -> Void) {
        switch dataStoreForReads {
        case .grdb:
            do {
                try grdbStorage.read { transaction in
                    block(transaction.asAnyRead)
                }
            } catch {
                owsFail("error: \(error.grdbErrorForLogging)")
            }
        case .ydb:
            yapStorage.read { transaction in
                block(transaction.asAnyRead)
            }
        }
    }

    @objc
    public override func write(block: @escaping (SDSAnyWriteTransaction) -> Void) {
        if OWSIsDebugBuild() &&
            Thread.isMainThread &&
            AppReadiness.isAppReady() {
            Logger.verbose("Database write on main thread.")
        }

        switch dataStoreForWrites {
        case .grdb:
            do {
                try grdbStorage.write { transaction in
                    Bench(title: "Slow Write Transaction", logIfLongerThan: 0.1) {
                        block(transaction.asAnyWrite)
                    }
                }
            } catch {
                owsFail("error: \(error.grdbErrorForLogging)")
            }
        case .ydb:
            yapStorage.write { transaction in
                Bench(title: "Slow Write Transaction", logIfLongerThan: 0.1) {
                    block(transaction.asAnyWrite)
                }
            }
        }
        crossProcess.notifyChangedAsync()
    }

    public func uiReadThrows(block: @escaping (SDSAnyReadTransaction) throws -> Void) throws {
        switch dataStoreForReads {
        case .grdb:
            try grdbStorage.uiReadThrows { transaction in
                try autoreleasepool {
                    try block(transaction.asAnyRead)
                }
            }
        case .ydb:
            try yapStorage.uiReadThrows { transaction in
                try block(transaction.asAnyRead)
            }
        }
    }

    public func uiread<T>(block: @escaping (SDSAnyReadTransaction) -> T) -> T {
        var value: T!
        uiRead { (transaction) in
            value = block(transaction)
        }
        return value
    }
}

// MARK: - Coordination

extension SDSDatabaseStorage {

    private var storageCoordinatorState: StorageCoordinatorState {
        guard let delegate = delegate else {
            owsFail("Missing delegate.")
        }
        return delegate.storageCoordinatorState
    }

    private var storageCoordinatorStateDescription: String {
        return NSStringFromStorageCoordinatorState(storageCoordinatorState)
    }

    @objc
    var dataStoreForReads: DataStore {
        // Before the migration starts and during the migration, read from YDB.
        switch storageCoordinatorState {
        case .YDB, .beforeYDBToGRDBMigration, .duringYDBToGRDBMigration:
            return .ydb
        case .GRDB:
            return .grdb
        case .ydbTests:
            return .ydb
        case .grdbTests:
            return .grdb
        }
    }

    @objc
    var dataStoreForWrites: DataStore {
        // Before the migration starts (but NOT during the migration), write to YDB.
        switch storageCoordinatorState {
        case .YDB, .beforeYDBToGRDBMigration:
            return .ydb
        case .duringYDBToGRDBMigration, .GRDB:
            return .grdb
        case .ydbTests:
            return .ydb
        case .grdbTests:
            return .grdb
        }
    }

    private var dataStoreForReporting: DataStore {
        return StorageCoordinator.dataStoreForUI
    }

    @objc
    var canLoadYdb: Bool {
        switch storageCoordinatorState {
        case .YDB, .beforeYDBToGRDBMigration, .duringYDBToGRDBMigration:
            return true
        case .GRDB:
            return false
        case .ydbTests, .grdbTests:
            return true
        }
    }

    @objc
    var canReadFromYdb: Bool {
        // We can read from YDB before and during the YDB-to-GRDB migration.
        switch storageCoordinatorState {
        case .YDB, .beforeYDBToGRDBMigration, .duringYDBToGRDBMigration:
            return true
        case .GRDB:
            return false
        case .ydbTests, .grdbTests:
            return true
        }
    }

    @objc
    var canWriteToYdb: Bool {
        // We can write to YDB before but not during the YDB-to-GRDB migration.
        switch storageCoordinatorState {
        case .YDB, .beforeYDBToGRDBMigration:
            return true
        case .duringYDBToGRDBMigration, .GRDB:
            return false
        case .ydbTests, .grdbTests:
            return true
        }
    }

    @objc
    var canLoadGrdb: Bool {
        switch storageCoordinatorState {
        case .YDB:
            return false
        case .beforeYDBToGRDBMigration, .duringYDBToGRDBMigration, .GRDB:
            return true
        case .ydbTests, .grdbTests:
            return true
        }
    }

    @objc
    var canReadFromGrdb: Bool {
        // We can read from GRDB during but not before the YDB-to-GRDB migration.
        switch storageCoordinatorState {
        case .YDB, .beforeYDBToGRDBMigration:
            return false
        case .duringYDBToGRDBMigration, .GRDB:
            return true
        case .ydbTests, .grdbTests:
            return true
        }
    }

    @objc
    var canWriteToGrdb: Bool {
        // We can write to GRDB during but not before the YDB-to-GRDB migration.
        switch storageCoordinatorState {
        case .YDB, .beforeYDBToGRDBMigration:
            return false
        case .duringYDBToGRDBMigration, .GRDB:
            return true
        case .ydbTests, .grdbTests:
            return true
        }
    }
}

// MARK: -

protocol SDSDatabaseStorageAdapter {
    associatedtype ReadTransaction
    associatedtype WriteTransaction
    func uiRead(block: @escaping (ReadTransaction) -> Void) throws
    func read(block: @escaping (ReadTransaction) -> Void) throws
    func write(block: @escaping (WriteTransaction) -> Void) throws
}

// MARK: -

@objc
public class SDS: NSObject {
    @objc
    public class func fitsInInt64(_ value: UInt64) -> Bool {
        return value <= Int64.max
    }

    @objc
    public func fitsInInt64(_ value: UInt64) -> Bool {
        return SDS.fitsInInt64(value)
    }

    @objc(fitsInInt64WithNSNumber:)
    public class func fitsInInt64(nsNumber value: NSNumber) -> Bool {
        return fitsInInt64(value.uint64Value)
    }

    @objc(fitsInInt64WithNSNumber:)
    public func fitsInInt64(nsNumber value: NSNumber) -> Bool {
        return SDS.fitsInInt64(nsNumber: value)
    }
}

// MARK: -

@objc
public extension SDSDatabaseStorage {
    func logFileSizes() {
        Logger.info("Database : \(databaseFileSize)")
        Logger.info("\t WAL file size: \(databaseWALFileSize)")
        Logger.info("\t SHM file size: \(databaseSHMFileSize)")
    }

    func logAllFileSizes() {
        if canLoadYdb {
            Logger.info("YDB Database : \(yapStorage.databaseFileSize)")
            Logger.info("\t YDB WAL file size: \(yapStorage.databaseWALFileSize)")
            Logger.info("\t YDB SHM file size: \(yapStorage.databaseSHMFileSize)")
        }
        if canLoadGrdb {
            Logger.info("GDRB Database : \(grdbStorage.databaseFileSize)")
            Logger.info("\t GDRB WAL file size: \(grdbStorage.databaseWALFileSize)")
            Logger.info("\t GDRB SHM file size: \(grdbStorage.databaseSHMFileSize)")
        }
    }

    var databaseFileSize: UInt64 {
        switch dataStoreForReporting {
        case .grdb:
            return grdbStorage.databaseFileSize
        case .ydb:
            return yapStorage.databaseFileSize
        }
    }

    var databaseWALFileSize: UInt64 {
        switch dataStoreForReporting {
        case .grdb:
            return grdbStorage.databaseWALFileSize
        case .ydb:
            return yapStorage.databaseWALFileSize
        }
    }

    var databaseSHMFileSize: UInt64 {
        switch dataStoreForReporting {
        case .grdb:
            return grdbStorage.databaseSHMFileSize
        case .ydb:
            return yapStorage.databaseSHMFileSize
        }
    }
}
