//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class SSKPreferences: NSObject {
    private static var shared: SSKPreferences {
        return SSKEnvironment.shared.sskPreferences
    }

    public static let store = SDSKeyValueStore(collection: "SSKPreferences")

    private var store: SDSKeyValueStore {
        return SSKPreferences.store
    }

    // MARK: -

    private static let areLinkPreviewsEnabledKey = "areLinkPreviewsEnabled"

    @objc
    public static func areLinkPreviewsEnabled(transaction: SDSAnyReadTransaction) -> Bool {
        return store.getBool(areLinkPreviewsEnabledKey, defaultValue: true, transaction: transaction)
    }

    @objc
    public static func setAreLinkPreviewsEnabledAndSendSyncMessage(_ newValue: Bool, transaction: SDSAnyWriteTransaction) {
        setAreLinkPreviewsEnabled(newValue, transaction: transaction)
        SSKEnvironment.shared.syncManager.sendConfigurationSyncMessage()
    }

    @objc
    public static func setAreLinkPreviewsEnabled(_ newValue: Bool, transaction: SDSAnyWriteTransaction) {
        store.setBool(newValue, key: areLinkPreviewsEnabledKey, transaction: transaction)
    }

    // MARK: -

    @objc
    public static func hasSavedThread(transaction: SDSAnyReadTransaction) -> Bool {
        return shared.hasSavedThread(transaction: transaction)
    }

    @objc
    public static func setHasSavedThread(_ newValue: Bool, transaction: SDSAnyWriteTransaction) {
        shared.setHasSavedThread(newValue, transaction: transaction)
    }

    private let hasSavedThreadKey = "hasSavedThread"
    // Only access this queue within db transactions.
    private var hasSavedThreadCache: Bool?

    @objc
    public func hasSavedThread(transaction: SDSAnyReadTransaction) -> Bool {
        if let value = hasSavedThreadCache {
            return value
        }
        let value = store.getBool(hasSavedThreadKey, defaultValue: false, transaction: transaction)
        hasSavedThreadCache = value
        return value
    }

    @objc
    public func setHasSavedThread(_ newValue: Bool, transaction: SDSAnyWriteTransaction) {
        store.setBool(newValue, key: hasSavedThreadKey, transaction: transaction)
        hasSavedThreadCache = newValue
    }

    // MARK: -

    private static let isYdbMigratedKey = "isYdbMigrated1"

    @objc
    public static func isYdbMigrated() -> Bool {
        let appUserDefaults = CurrentAppContext().appUserDefaults()
        guard let preference = appUserDefaults.object(forKey: isYdbMigratedKey) as? NSNumber else {
            return false
        }
        return preference.boolValue
    }

    @objc
    public static func setIsYdbMigrated(_ value: Bool) {
        let appUserDefaults = CurrentAppContext().appUserDefaults()
        appUserDefaults.set(value, forKey: isYdbMigratedKey)
        appUserDefaults.synchronize()
    }

    // MARK: -

    private static let didEverUseYdbKey = "didEverUseYdb"

    @objc
    public static func didEverUseYdb() -> Bool {
        let appUserDefaults = CurrentAppContext().appUserDefaults()
        guard let preference = appUserDefaults.object(forKey: didEverUseYdbKey) as? NSNumber else {
            return false
        }
        return preference.boolValue
    }

    @objc
    public static func setDidEverUseYdb(_ value: Bool) {
        let appUserDefaults = CurrentAppContext().appUserDefaults()
        appUserDefaults.set(value, forKey: didEverUseYdbKey)
        appUserDefaults.synchronize()
    }

    // MARK: -

    public class var grdbSchemaVersionDefault: UInt {
        return GRDBSchemaMigrator.grdbSchemaVersionDefault
    }
    public class var grdbSchemaVersionLatest: UInt {
        return GRDBSchemaMigrator.grdbSchemaVersionLatest
    }

    private static let grdbSchemaVersionKey = "grdbSchemaVersion"

    private static func grdbSchemaVersion() -> UInt {
        let appUserDefaults = CurrentAppContext().appUserDefaults()
        guard let preference = appUserDefaults.object(forKey: grdbSchemaVersionKey) as? NSNumber else {
            return grdbSchemaVersionDefault
        }
        return preference.uintValue
    }

    private static func setGrdbSchemaVersion(_ value: UInt) {
        let lastKnownGrdbSchemaVersion = grdbSchemaVersion()
        guard value != lastKnownGrdbSchemaVersion else {
            return
        }
        guard value > lastKnownGrdbSchemaVersion else {
            owsFailDebug("Reverting to earlier schema version: \(value)")
            return
        }
        Logger.info("Updating schema version: \(lastKnownGrdbSchemaVersion) -> \(value)")
        let appUserDefaults = CurrentAppContext().appUserDefaults()
        appUserDefaults.set(value, forKey: grdbSchemaVersionKey)
        appUserDefaults.synchronize()
    }

    @objc
    public static func markGRDBSchemaAsLatest() {
        setGrdbSchemaVersion(grdbSchemaVersionLatest)
    }

    @objc
    public static func hasUnknownGRDBSchema() -> Bool {
        guard grdbSchemaVersion() <= grdbSchemaVersionLatest else {
            owsFailDebug("grdbSchemaVersion: \(grdbSchemaVersion()), grdbSchemaVersionLatest: \(grdbSchemaVersionLatest)")
            return true
        }
        return false
    }
}
