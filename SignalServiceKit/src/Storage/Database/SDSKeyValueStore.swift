//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import GRDB
import SignalCoreKit

// This class can be used to:
//
// * Back a preferences class.
// * To persist simple values in our managers.
// * Etc.
@objc
public class SDSKeyValueStore: NSObject {

    // Key-value stores use "collections" to group related keys.
    //
    // * In YDB, we store each model type and k-v store in a separate YDB collection.
    // * In GRDB, we store each model in a separate table but
    //   all k-v stores are in a single table.
    //   GRDB maintains a mapping between tables and collections.
    //   For the purposes of this mapping only we use dataStoreCollection.
    static let dataStoreCollection = "keyvalue"
    static let tableName = "keyvalue"

    // By default, all reads/writes use this collection.
    @objc
    public let collection: String

    static let collectionColumn = SDSColumnMetadata(columnName: "collection", columnType: .unicodeString, isOptional: false)
    static let keyColumn = SDSColumnMetadata(columnName: "key", columnType: .unicodeString, isOptional: false)
    static let valueColumn = SDSColumnMetadata(columnName: "value", columnType: .blob, isOptional: false)
    // TODO: For now, store all key-value in a single table.
    public static let table = SDSTableMetadata(collection: SDSKeyValueStore.dataStoreCollection,
        tableName: SDSKeyValueStore.tableName,
        columns: [
        collectionColumn,
        keyColumn,
        valueColumn
        ])

    @objc
    public init(collection: String) {
        // TODO: Verify that collection is a valid table name _OR_ convert to valid name.
        self.collection = collection

        super.init()
    }

    public class func createTable(database: Database) throws {
        let sql = """
            CREATE TABLE \(table.tableName) (
                \(keyColumn.columnName) TEXT NOT NULL,
                \(collectionColumn.columnName) TEXT NOT NULL,
                \(valueColumn.columnName) BLOB NOT NULL,
                PRIMARY KEY (
                    \(keyColumn.columnName),
                    \(collectionColumn.columnName)
                )
            )
        """
        let statement = try database.makeUpdateStatement(sql: sql)
        try statement.execute()
    }

    // MARK: Class Helpers

    @objc
    public class func key(int: Int) -> String {
        return NSNumber(value: int).stringValue
    }

    @objc
    public func hasValue(forKey key: String, transaction: SDSAnyReadTransaction) -> Bool {
        switch transaction.readTransaction {
        case .yapRead(let ydbTransaction):
            return ydbTransaction.hasObject(forKey: key, inCollection: collection)
        case .grdbRead(let grdbTransaction):
            do {
                let count = try UInt.fetchOne(grdbTransaction.database,
                                              sql: """
                    SELECT
                    COUNT(*)
                    FROM \(SDSKeyValueStore.table.tableName)
                    WHERE \(SDSKeyValueStore.keyColumn.columnName) = ?
                    AND \(SDSKeyValueStore.collectionColumn.columnName) == ?
                    """,
                                              arguments: [key, collection]) ?? 0
                return count > 0
            } catch {
                owsFailDebug("error: \(error)")
                return false
            }
        }
    }

    // MARK: - String

    @objc
    public func getString(_ key: String, transaction: SDSAnyReadTransaction) -> String? {
        return read(key, transaction: transaction)
    }

    @objc
    public func setString(_ value: String?, key: String, transaction: SDSAnyWriteTransaction) {
        guard let value = value else {
            write(nil, forKey: key, transaction: transaction)
            return
        }
        write(value as NSString, forKey: key, transaction: transaction)
    }

    // MARK: - Date

    @objc
    public func getDate(_ key: String, transaction: SDSAnyReadTransaction) -> Date? {
        // Our legacy methods sometimes stored dates as NSNumber and
        // sometimes as NSDate, so we are permissive when decoding.
        guard let object: NSObject = read(key, transaction: transaction) else {
            return nil
        }
        if let date = object as? Date {
            return date
        }
        guard let epochInterval = object as? NSNumber else {
            owsFailDebug("Could not decode value: \(type(of: object)).")
            return nil
        }
        return Date(timeIntervalSince1970: epochInterval.doubleValue)
    }

    @objc
    public func setDate(_ value: Date, key: String, transaction: SDSAnyWriteTransaction) {
        let epochInterval = NSNumber(value: value.timeIntervalSince1970)
        setObject(epochInterval, key: key, transaction: transaction)
    }

    // MARK: - Bool

    public func getBool(_ key: String, transaction: SDSAnyReadTransaction) -> Bool? {
        guard let number: NSNumber = read(key, transaction: transaction) else {
            return nil
        }
        return number.boolValue
    }

    @objc
    public func getBool(_ key: String, defaultValue: Bool, transaction: SDSAnyReadTransaction) -> Bool {
        return getBool(key, transaction: transaction) ?? defaultValue
    }

    @objc
    public func setBool(_ value: Bool, key: String, transaction: SDSAnyWriteTransaction) {
        write(NSNumber(booleanLiteral: value), forKey: key, transaction: transaction)
    }

    // MARK: - UInt

    public func getUInt(_ key: String, transaction: SDSAnyReadTransaction) -> UInt? {
        guard let number: NSNumber = read(key, transaction: transaction) else {
            return nil
        }
        return number.uintValue
    }

    // TODO: Handle numerics more generally.
    @objc
    public func getUInt(_ key: String, defaultValue: UInt, transaction: SDSAnyReadTransaction) -> UInt {
        return getUInt(key, transaction: transaction) ?? defaultValue
    }

    @objc
    public func setUInt(_ value: UInt, key: String, transaction: SDSAnyWriteTransaction) {
        write(NSNumber(value: value), forKey: key, transaction: transaction)
    }

    // MARK: - Data

    @objc
    public func getData(_ key: String, transaction: SDSAnyReadTransaction) -> Data? {
        return readData(key, transaction: transaction)
    }

    @objc
    public func setData(_ value: Data?, key: String, transaction: SDSAnyWriteTransaction) {
        writeData(value, forKey: key, transaction: transaction)
    }

    // MARK: - Numeric

    @objc
    public func getNSNumber(_ key: String, transaction: SDSAnyReadTransaction) -> NSNumber? {
        let number: NSNumber? = read(key, transaction: transaction)
        return number
    }

    // MARK: - Int

    public func getInt(_ key: String, transaction: SDSAnyReadTransaction) -> Int? {
        guard let number: NSNumber = read(key, transaction: transaction) else {
            return nil
        }
        return number.intValue
    }

    @objc
    public func getInt(_ key: String, defaultValue: Int, transaction: SDSAnyReadTransaction) -> Int {
        return getInt(key, transaction: transaction) ?? defaultValue
    }

    @objc
    public func setInt(_ value: Int, key: String, transaction: SDSAnyWriteTransaction) {
        setObject(NSNumber(value: value), key: key, transaction: transaction)
    }

    // MARK: - UInt32

    public func getUInt32(_ key: String, transaction: SDSAnyReadTransaction) -> UInt32? {
        guard let number: NSNumber = read(key, transaction: transaction) else {
            return nil
        }
        return number.uint32Value
    }

    @objc
    public func getUInt32(_ key: String, defaultValue: UInt32, transaction: SDSAnyReadTransaction) -> UInt32 {
        return getUInt32(key, transaction: transaction) ?? defaultValue
    }

    @objc
    public func setUInt32(_ value: UInt32, key: String, transaction: SDSAnyWriteTransaction) {
        setObject(NSNumber(value: value), key: key, transaction: transaction)
    }

    // MARK: - UInt64

    public func getUInt64(_ key: String, transaction: SDSAnyReadTransaction) -> UInt64? {
        guard let number: NSNumber = read(key, transaction: transaction) else {
            return nil
        }
        return number.uint64Value
    }

    @objc
    public func getUInt64(_ key: String, defaultValue: UInt64, transaction: SDSAnyReadTransaction) -> UInt64 {
        return getUInt64(key, transaction: transaction) ?? defaultValue
    }

    @objc
    public func setUInt64(_ value: UInt64, key: String, transaction: SDSAnyWriteTransaction) {
        setObject(NSNumber(value: value), key: key, transaction: transaction)
    }

    // MARK: - Double

    public func getDouble(_ key: String, transaction: SDSAnyReadTransaction) -> Double? {
        guard let number: NSNumber = read(key, transaction: transaction) else {
            return nil
        }
        return number.doubleValue
    }

    @objc
    public func getDouble(_ key: String, defaultValue: Double, transaction: SDSAnyReadTransaction) -> Double {
        return getDouble(key, transaction: transaction) ?? defaultValue
    }

    @objc
    public func setDouble(_ value: Double, key: String, transaction: SDSAnyWriteTransaction) {
        setObject(NSNumber(value: value), key: key, transaction: transaction)
    }

    // MARK: - Object

    @objc
    public func getObject(_ key: String, transaction: SDSAnyReadTransaction) -> Any? {
        return read(key, transaction: transaction)
    }

    @objc
    public func setObject(_ anyValue: Any?, key: String, transaction: SDSAnyWriteTransaction) {
        guard let anyValue = anyValue else {
            write(nil, forKey: key, transaction: transaction)
            return
        }
        guard let codingValue = anyValue as? NSCoding else {
            owsFailDebug("Invalid value.")
            write(nil, forKey: key, transaction: transaction)
            return
        }
        write(codingValue, forKey: key, transaction: transaction)
    }

    @objc
    public func removeValue(forKey key: String, transaction: SDSAnyWriteTransaction) {
        write(nil, forKey: key, transaction: transaction)
    }

    @objc
    public func removeValues(forKeys keys: [String], transaction: SDSAnyWriteTransaction) {
        for key in keys {
            write(nil, forKey: key, transaction: transaction)
        }
    }

    @objc
    public func removeAll(transaction: SDSAnyWriteTransaction) {
        switch transaction.writeTransaction {
        case .yapWrite(let yapWrite):
            yapWrite.removeAllObjects(inCollection: collection)
        case .grdbWrite(let grdbWrite):
            let sql = """
                DELETE
                FROM \(SDSKeyValueStore.table.tableName)
                WHERE \(SDSKeyValueStore.collectionColumn.columnName) == ?
            """
            grdbWrite.executeWithCachedStatement(sql: sql, arguments: [collection])
        }
    }

    @objc
    public func enumerateKeysAndObjects(transaction: SDSAnyReadTransaction, block: @escaping (String, Any, UnsafeMutablePointer<ObjCBool>) -> Void) {
        switch transaction.readTransaction {
        case .yapRead(let ydbTransaction):
            ydbTransaction.enumerateKeysAndObjects(inCollection: collection) { (key: String, value: Any, stopPtr: UnsafeMutablePointer<ObjCBool>) in
                block(key, value, stopPtr)
            }
        case .grdbRead(let grdbRead):
            var stop: ObjCBool = false
            // PERF - we could enumerate with a single query rather than
            // fetching keys then fetching objects one by one. In practice
            // the collections that use this are pretty small.
            for key in allKeys(grdbTransaction: grdbRead) {
                guard !stop.boolValue else {
                    return
                }
                guard let value: Any = read(key, transaction: transaction) else {
                    owsFailDebug("value was unexpectedly nil")
                    continue
                }
                block(key, value, &stop)
            }
        }
    }

    @objc
    public func enumerateKeys(transaction: SDSAnyReadTransaction, block: @escaping (String, UnsafeMutablePointer<ObjCBool>) -> Void) {
        switch transaction.readTransaction {
        case .yapRead(let ydbTransaction):
            ydbTransaction.enumerateKeys(inCollection: collection) { (key: String, stopPtr: UnsafeMutablePointer<ObjCBool>) in
                block(key, stopPtr)
            }
        case .grdbRead(let grdbRead):
            var stop: ObjCBool = false
            for key in allKeys(grdbTransaction: grdbRead) {
                guard !stop.boolValue else {
                    return
                }
                block(key, &stop)
            }
        }
    }

    @objc
    public func allValues(transaction: SDSAnyReadTransaction) -> [Any] {
        return allKeys(transaction: transaction).map { key in
            return self.read(key, transaction: transaction)
        }
    }

    @objc
    public func allKeys(transaction: SDSAnyReadTransaction) -> [String] {
        switch transaction.readTransaction {
        case .yapRead(let ydbTransaction):
            return ydbTransaction.allKeys(inCollection: collection)
        case .grdbRead(let grdbRead):
            return allKeys(grdbTransaction: grdbRead)
        }
    }

    @objc
    public func numberOfKeys(transaction: SDSAnyReadTransaction) -> UInt {
        switch transaction.readTransaction {
        case .yapRead(let ydbTransaction):
            return ydbTransaction.numberOfKeys(inCollection: collection)
        case .grdbRead(let grdbRead):
            let sql = """
            SELECT COUNT(*)
            FROM \(SDSKeyValueStore.table.tableName)
            WHERE \(SDSKeyValueStore.collectionColumn.columnName) == ?
            """
            do {
                guard let numberOfKeys = try UInt.fetchOne(grdbRead.database,
                                                           sql: sql,
                                                           arguments: [collection]) else {
                                                            throw OWSErrorMakeAssertionError("numberOfKeys was unexpectedly nil")
                }
                return numberOfKeys
            } catch {
                owsFail("error: \(error)")
            }
        }
    }

    @objc
    var asObjC: SDSKeyValueStoreObjC {
        return SDSKeyValueStoreObjC(sdsKeyValueStore: self)
    }

    // MARK: - Internal Methods

    private func read<T>(_ key: String, transaction: SDSAnyReadTransaction) -> T? {
        guard let rawObject = readRawObject(key, transaction: transaction) else {
            return nil
        }
        guard let object = rawObject as? T else {
            owsFailDebug("Value for key: \(key) has unexpected type: \(type(of: rawObject)).")
            return nil
        }
        return object
    }

    private func readRawObject(_ key: String, transaction: SDSAnyReadTransaction) -> Any? {
        // YDB values are serialized by YDB.
        // GRDB values are serialized to data by this class.
        switch transaction.readTransaction {
        case .yapRead(let ydbTransaction):
            return ydbTransaction.object(forKey: key, inCollection: collection)
        case .grdbRead:
            guard let encoded = readData(key, transaction: transaction) else {
                return nil
            }

            do {
                guard let rawObject = try NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(encoded) else {
                    owsFailDebug("Could not decode value.")
                    return nil
                }
                return rawObject
            } catch {
                owsFailDebug("Decode failed.")
                return nil
            }
        }
    }

    private func readData(_ key: String, transaction: SDSAnyReadTransaction) -> Data? {
        let collection = self.collection

        switch transaction.readTransaction {
        case .yapRead(let ydbTransaction):
            guard let rawObject = ydbTransaction.object(forKey: key, inCollection: collection) else {
                return nil
            }
            guard let object = rawObject as? Data else {
                owsFailDebug("Value has unexpected type: \(type(of: rawObject)).")
                return nil
            }
            return object
        case .grdbRead(let grdbTransaction):
            return SDSKeyValueStore.readData(transaction: grdbTransaction, key: key, collection: collection)
        }
    }

    private class func readData(transaction: GRDBReadTransaction, key: String, collection: String) -> Data? {
        do {
            return try Data.fetchOne(transaction.database,
                                     sql: "SELECT \(self.valueColumn.columnName) FROM \(self.table.tableName) WHERE \(self.keyColumn.columnName) = ? AND \(collectionColumn.columnName) == ?",
                arguments: [key, collection])
        } catch {
            owsFailDebug("error: \(error)")
            return nil
        }
    }

    // TODO: Codable? NSCoding? Other serialization?
    private func write(_ value: NSCoding?, forKey key: String, transaction: SDSAnyWriteTransaction) {
        // YDB values are serialized by YDB.
        // GRDB values are serialized to data by this class.
        switch transaction.writeTransaction {
        case .yapWrite(let ydbTransaction):
            if let value = value {
                ydbTransaction.setObject(value, forKey: key, inCollection: collection)
            } else {
                ydbTransaction.removeObject(forKey: key, inCollection: collection)
            }
        case .grdbWrite:
            if let value = value {
                let encoded = NSKeyedArchiver.archivedData(withRootObject: value)
                writeData(encoded, forKey: key, transaction: transaction)
            } else {
                writeData(nil, forKey: key, transaction: transaction)
            }
        }
    }

    private func writeData(_ data: Data?, forKey key: String, transaction: SDSAnyWriteTransaction) {

        let collection = self.collection

        switch transaction.writeTransaction {
        case .yapWrite(let ydbTransaction):
            if let data = data {
                ydbTransaction.setObject(data, forKey: key, inCollection: collection)
            } else {
                ydbTransaction.removeObject(forKey: key, inCollection: collection)
            }
        case .grdbWrite(let grdbTransaction):
            do {
                try SDSKeyValueStore.write(transaction: grdbTransaction, key: key, collection: collection, encoded: data)
            } catch {
                owsFailDebug("error: \(error)")
            }
        }
    }

    private class func write(transaction: GRDBWriteTransaction, key: String, collection: String, encoded: Data?) throws {
        if let encoded = encoded {
            // See: https://www.sqlite.org/lang_UPSERT.html
            let sql = """
                INSERT INTO \(table.tableName) (
                    \(keyColumn.columnName),
                    \(collectionColumn.columnName),
                    \(valueColumn.columnName)
                ) VALUES (?, ?, ?)
                ON CONFLICT (
                    \(keyColumn.columnName),
                    \(collectionColumn.columnName)
                ) DO UPDATE
                SET \(valueColumn.columnName) = ?
            """
            try update(transaction: transaction, sql: sql, arguments: [ key, collection, encoded, encoded ])
        } else {
            // Setting to nil is a delete.
            let sql = "DELETE FROM \(table.tableName) WHERE \(keyColumn.columnName) == ? AND \(collectionColumn.columnName) == ?"
            try update(transaction: transaction, sql: sql, arguments: [ key, collection ])
        }
    }

    private class func update(transaction: GRDBWriteTransaction,
                        sql: String,
                        arguments: [DatabaseValueConvertible]) throws {

        let statement = try transaction.database.cachedUpdateStatement(sql: sql)
        guard let statementArguments = StatementArguments(arguments) else {
            owsFailDebug("Could not convert values.")
            return
        }
        // TODO: We could use setArgumentsWithValidation for more safety.
        statement.unsafeSetArguments(statementArguments)
        try statement.execute()
    }

    private func allKeys(grdbTransaction: GRDBReadTransaction) -> [String] {
        let sql = """
        SELECT \(SDSKeyValueStore.keyColumn.columnName)
        FROM \(SDSKeyValueStore.table.tableName)
        WHERE \(SDSKeyValueStore.collectionColumn.columnName) == ?
        """
        return try! String.fetchAll(grdbTransaction.database,
                                    sql: sql,
                                    arguments: [collection])
    }
}
