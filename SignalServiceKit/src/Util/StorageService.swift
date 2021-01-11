//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

@objc
public protocol StorageServiceManagerProtocol {
    func recordPendingDeletions(deletedIds: [AccountId])
    func recordPendingDeletions(deletedAddresses: [SignalServiceAddress])

    func recordPendingUpdates(updatedIds: [AccountId])
    func recordPendingUpdates(updatedAddresses: [SignalServiceAddress])

    func backupPendingChanges()
    func restoreOrCreateManifestIfNecessary()
}

public struct StorageService {
    public enum StorageError: OperationError {
        case assertion
        case retryableAssertion
        case decryptionFailed(manifestVersion: UInt64)

        public var isRetryable: Bool {
            guard case .retryableAssertion = self else { return false }
            return true
        }
    }

    /// An identifier representing a given storage item.
    /// This can be used to fetch specific items from the service.
    public struct StorageIdentifier: Hashable {
        public static let identifierLength: Int32 = 16
        public let data: Data

        public init(data: Data) {
            if data.count != StorageIdentifier.identifierLength { owsFail("Initialized with invalid data") }
            self.data = data
        }

        public static func generate() -> StorageIdentifier {
            return .init(data: Randomness.generateRandomBytes(identifierLength))
        }
    }

    public struct StorageItem {
        public let identifier: StorageIdentifier
        public let record: StorageServiceProtoStorageRecord

        public var type: UInt32 { return record.type }

        public var contactRecord: StorageServiceProtoContactRecord? {
            guard type == StorageServiceProtoStorageRecordType.contact.rawValue else { return nil }
            guard let contact = record.contact else {
                owsFailDebug("unexpectedly missing contact record")
                return nil
            }
            return contact
        }

        public init(identifier: StorageIdentifier, contact: StorageServiceProtoContactRecord) throws {
            let storageRecord = StorageServiceProtoStorageRecord.builder(type: UInt32(StorageServiceProtoStorageRecordType.contact.rawValue))
            storageRecord.setContact(contact)
            self.init(identifier: identifier, record: try storageRecord.build())
        }

        public init(identifier: StorageIdentifier, record: StorageServiceProtoStorageRecord) {
            self.identifier = identifier
            self.record = record
        }
    }

    /// Fetch the latest manifest from the storage service
    ///
    /// Returns nil if a manifest has never been stored.
    public static func fetchManifest() -> Promise<StorageServiceProtoManifestRecord?> {
        Logger.info("")

        return storageRequest(withMethod: "GET", endpoint: "v1/storage/manifest").map(on: .global()) { response in
            switch response.status {
            case .success:
                let encryptedManifestContainer = try StorageServiceProtoStorageManifest.parseData(response.data)
                let manifestData: Data
                do {
                    manifestData = try KeyBackupService.decrypt(keyType: .storageService, encryptedData: encryptedManifestContainer.value)
                } catch {
                    throw StorageError.decryptionFailed(manifestVersion: encryptedManifestContainer.version)
                }
                return try StorageServiceProtoManifestRecord.parseData(manifestData)
            case .notFound:
                return nil
            default:
                owsFailDebug("unexpected response \(response.status)")
                throw StorageError.retryableAssertion
            }
        }
    }

    /// Update the manifest record on the service.
    ///
    /// If the version we are updating to already exists on the service,
    /// the conflicting manifest will return and the update will not
    /// have been applied until we resolve the conflicts.
    public static func updateManifest(
        _ manifest: StorageServiceProtoManifestRecord,
        newItems: [StorageItem],
        deletedIdentifiers: [StorageIdentifier]
    ) -> Promise<StorageServiceProtoManifestRecord?> {
        Logger.info("")

        return DispatchQueue.global().async(.promise) {
            let builder = StorageServiceProtoWriteOperation.builder()

            // Encrypt the manifest
            let manifestData = try manifest.serializedData()
            let encryptedManifestData = try KeyBackupService.encrypt(keyType: .storageService, data: manifestData)

            let manifestWrapperBuilder = StorageServiceProtoStorageManifest.builder(
                version: manifest.version,
                value: encryptedManifestData
            )
            builder.setManifest(try manifestWrapperBuilder.build())

            // Encrypt the new items
            builder.setInsertItem(try newItems.map { item in
                let itemData = try item.record.serializedData()
                let encryptedItemData = try KeyBackupService.encrypt(keyType: .storageService, data: itemData)
                let itemWrapperBuilder = StorageServiceProtoStorageItem.builder(key: item.identifier.data, value: encryptedItemData)
                return try itemWrapperBuilder.build()
            })

            // Flag the deleted keys
            builder.setDeleteKey(deletedIdentifiers.map { $0.data })

            return try builder.buildSerializedData()
        }.then(on: .global()) { data in
            storageRequest(withMethod: "PUT", endpoint: "/v1/storage", body: data)
        }.map(on: .global()) { response in
            switch response.status {
            case .success:
                // We expect a successful response to have no data
                if !response.data.isEmpty { owsFailDebug("unexpected response data") }
                return nil
            case .conflict:
                // Our version was out of date, we should've received a copy of the latest version
                let encryptedManifestData = try StorageServiceProtoStorageManifest.parseData(response.data).value
                let manifestData = try KeyBackupService.decrypt(keyType: .storageService, encryptedData: encryptedManifestData)
                return try StorageServiceProtoManifestRecord.parseData(manifestData)
            default:
                owsFailDebug("unexpected response \(response.status)")
                throw StorageError.retryableAssertion
            }
        }
    }

    /// Fetch an item record from the service
    ///
    /// Returns nil if this record does not exist
    public static func fetchItem(for key: StorageIdentifier) -> Promise<StorageItem?> {
        return fetchItems(for: [key]).map { $0.first }
    }

    /// Fetch a list of item records from the service
    ///
    /// The response will include only the items that could be found on the service
    public static func fetchItems(for keys: [StorageIdentifier]) -> Promise<[StorageItem]> {
        Logger.info("")

        return DispatchQueue.global().async(.promise) {
            let builder = StorageServiceProtoReadOperation.builder()
            builder.setReadKey(keys.map { $0.data })
            return try builder.buildSerializedData()
        }.then(on: .global()) { data in
            storageRequest(withMethod: "PUT", endpoint: "v1/storage/read", body: data)
        }.map(on: .global()) { response in
            guard case .success = response.status else {
                owsFailDebug("unexpected response \(response.status)")
                throw StorageError.retryableAssertion
            }

            let itemsProto = try StorageServiceProtoStorageItems.parseData(response.data)

            return try itemsProto.items.map { item in
                let encryptedItemData = item.value
                let itemData = try KeyBackupService.decrypt(keyType: .storageService, encryptedData: encryptedItemData)
                let record = try StorageServiceProtoStorageRecord.parseData(itemData)
                return StorageItem(identifier: StorageIdentifier(data: item.key), record: record)
            }
        }
    }

    // MARK: - Dependencies

    private static var sessionManager: AFHTTPSessionManager {
        return OWSSignalService.sharedInstance().storageServiceSessionManager
    }

    private static var signalServiceClient: SignalServiceClient {
        return SignalServiceRestClient()
    }

    // MARK: - Storage Requests

    private struct StorageResponse {
        enum Status {
            case success
            case conflict
            case notFound
        }
        let status: Status
        let data: Data
    }

    private struct Auth {
        let username: String
        let password: String

        func authHeader() throws -> String {
            guard let data = "\(username):\(password)".data(using: .utf8) else {
                owsFailDebug("failed to encode auth data")
                throw StorageError.assertion
            }
            return "Basic " + data.base64EncodedString()
        }
    }

    private static func storageRequest(withMethod method: String, endpoint: String, body: Data? = nil) -> Promise<StorageResponse> {
        return signalServiceClient.requestStorageAuth().map { username, password in
            Auth(username: username, password: password)
        }.then(on: .global()) { auth in
            Promise { resolver in
                guard let url = URL(string: endpoint, relativeTo: sessionManager.baseURL) else {
                    owsFailDebug("failed to initialize URL")
                    throw StorageError.assertion
                }

                var error: NSError?
                let request = sessionManager.requestSerializer.request(
                    withMethod: method,
                    urlString: url.absoluteString,
                    parameters: nil,
                    error: &error
                )

                if let error = error {
                    owsFailDebug("failed to generate request: \(error)")
                    throw StorageError.assertion
                }

                if method == "GET" { assert(body == nil) }

                request.httpBody = body

                request.setValue(OWSMimeTypeProtobuf, forHTTPHeaderField: "Content-Type")
                request.setValue(try auth.authHeader(), forHTTPHeaderField: "Authorization")

                Logger.info("Storage request started: \(method) \(endpoint)")

                let task = sessionManager.dataTask(
                    with: request as URLRequest,
                    uploadProgress: nil,
                    downloadProgress: nil
                ) { response, responseObject, error in
                    guard let response = response as? HTTPURLResponse else {
                        Logger.info("Storage request failed: \(method) \(endpoint)")

                        guard let error = error else {
                            owsFailDebug("unexpected response type")
                            return resolver.reject(StorageError.assertion)
                        }

                        owsFailDebug("response error \(error)")
                        return resolver.reject(error)
                    }

                    let status: StorageResponse.Status

                    switch response.statusCode {
                    case 200:
                        status = .success
                    case 409:
                        status = .conflict
                    case 404:
                        status = .notFound
                    default:
                        owsFailDebug("invalid response \(response.statusCode)")
                        if response.statusCode >= 500 {
                            // This is a server error, retry
                            return resolver.reject(StorageError.retryableAssertion)
                        } else if let error = error {
                            return resolver.reject(error)
                        } else {
                            return resolver.reject(StorageError.assertion)
                        }
                    }

                    // We should always receive response data, for some responses it will be empty.
                    guard let responseData = responseObject as? Data else {
                        owsFailDebug("missing response data")
                        return resolver.reject(StorageError.retryableAssertion)
                    }

                    // The layers that use this only want to process 200 and 409 responses,
                    // anything else we should raise as an error.

                    Logger.info("Storage request succeeded: \(method) \(endpoint)")

                    resolver.fulfill(StorageResponse(status: status, data: responseData))
                }
                task.resume()
            }
        }
    }
}

// MARK: - Test Helpers

#if DEBUG

public extension StorageService {
    static func test() {
        let testNames = ["abc", "def", "ghi", "jkl", "mno"]
        var recordsInManifest = [StorageItem]()
        for i in 0...4 {
            let identifier = StorageService.StorageIdentifier.generate()

            let contactRecordBuilder = StorageServiceProtoContactRecord.builder()
            contactRecordBuilder.setServiceUuid(testNames[i])

            recordsInManifest.append(try! StorageItem(identifier: identifier, contact: try! contactRecordBuilder.build()))
        }

        let identifiersInManfest = recordsInManifest.map { $0.identifier }

        var ourManifestVersion: UInt64 = 0

        // Fetch Existing
        fetchManifest().map { manifest in
            let previousVersion = manifest?.version ?? ourManifestVersion
            ourManifestVersion = previousVersion + 1

            // set keys
            let newManifestBuilder = StorageServiceProtoManifestRecord.builder(version: ourManifestVersion)
            newManifestBuilder.setKeys(recordsInManifest.map { $0.identifier.data })

            return (try! newManifestBuilder.build(), manifest?.keys.map { StorageIdentifier(data: $0) } ?? [])

        // Update or create initial manifest with test data
        }.then { manifest, deletedKeys in
            updateManifest(manifest, newItems: recordsInManifest, deletedIdentifiers: deletedKeys)
        }.map { manifest in
            guard manifest == nil else {
                owsFailDebug("Manifest conflicted unexpectedly, should be nil")
                throw StorageError.assertion
            }

        // Fetch the manifest we just created
        }.then { fetchManifest() }.map { manifest in
            guard let manifest = manifest else {
                owsFailDebug("manifest should exist, we just created it")
                throw StorageError.assertion
            }

            guard Set(manifest.keys) == Set(identifiersInManfest.map { $0.data }) else {
                owsFailDebug("manifest should only contain our test keys")
                throw StorageError.assertion
            }

            guard manifest.version == ourManifestVersion else {
                owsFailDebug("manifest version should be the version we set")
                throw StorageError.assertion
            }

        // Fetch the first contact we just stored
        }.then {
            fetchItem(for: identifiersInManfest.first!)
        }.map { item in
            guard let item = item, item.identifier == identifiersInManfest.first! else {
                owsFailDebug("this should be the contact we set")
                throw StorageError.assertion
            }

            guard item.contactRecord!.serviceUuid == recordsInManifest.first!.contactRecord!.serviceUuid else {
                owsFailDebug("this should be the contact we set")
                throw StorageError.assertion
            }

        // Fetch all the contacts we stored
        }.then {
            fetchItems(for: identifiersInManfest)
        }.map { items in
            guard items.count == recordsInManifest.count else {
                owsFailDebug("wrong number of contacts")
                throw StorageError.assertion
            }

            for item in items {
                guard let matchingRecord = recordsInManifest.first(where: { $0.identifier == item.identifier }) else {
                    owsFailDebug("this should be a contact we set")
                    throw StorageError.assertion
                }

                guard item.contactRecord!.serviceUuid == matchingRecord.contactRecord!.serviceUuid else {
                    owsFailDebug("this should be a contact we set")
                    throw StorageError.assertion
                }

            }

        // Fetch a contact that doesn't exist
        }.then {
            fetchItem(for: .generate())
        }.map { item in
            guard item == nil else {
                owsFailDebug("this contact should not exist")
                throw StorageError.assertion
            }

        // Delete all the contacts we stored
        }.map {
            ourManifestVersion += 1
            let newManifestBuilder = StorageServiceProtoManifestRecord.builder(version: ourManifestVersion)
            return try! newManifestBuilder.build()
        }.then { manifest in
            updateManifest(manifest, newItems: [], deletedIdentifiers: identifiersInManfest)
        }.map { manifest in
            guard manifest == nil else {
                owsFailDebug("Manifest conflicted unexpectedly, should be nil")
                throw StorageError.assertion
            }

        // Fetch the manifest we just stored
        }.then { fetchManifest() }.map { manifest in
            guard let manifest = manifest else {
                owsFailDebug("manifest should exist, we just created it")
                throw StorageError.assertion
            }

            guard manifest.keys.isEmpty else {
                owsFailDebug("manifest should have no keys")
                throw StorageError.assertion
            }

            guard manifest.version == ourManifestVersion else {
                owsFailDebug("manifest version should be the version we set")
                throw StorageError.assertion
            }

        // Try and update a manifest version that already exists
        }.map {
            let oldManifestBuilder = StorageServiceProtoManifestRecord.builder(version: 0)

            let identifier = StorageIdentifier.generate()

            let recordBuilder = StorageServiceProtoContactRecord.builder()
            recordBuilder.setServiceUuid(testNames[0])

            oldManifestBuilder.setKeys([identifier.data])

            return (try! oldManifestBuilder.build(), try! StorageItem(identifier: identifier, contact: try! recordBuilder.build()))
        }.then { oldManifest, item in
            updateManifest(oldManifest, newItems: [item], deletedIdentifiers: [])
        }.done { manifest in
            guard let manifest = manifest else {
                owsFailDebug("manifest should exist, because there was a conflict")
                throw StorageError.assertion
            }

            guard manifest.keys.isEmpty else {
                owsFailDebug("manifest should still have no keys")
                throw StorageError.assertion
            }

            guard manifest.version == ourManifestVersion else {
                owsFailDebug("manifest version should be the version we set")
                throw StorageError.assertion
            }
        }.catch { error in
            owsFailDebug("unexpectedly raised error \(error)")
        }.retainUntilComplete()
    }
}

#endif
