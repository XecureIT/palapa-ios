//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class AnyContactThreadFinder: NSObject {
    let grdbAdapter = GRDBContactThreadFinder()
    let yapdbAdapter = YAPDBSignalServiceAddressIndex()
}

public extension AnyContactThreadFinder {
    @objc(contactThreadForAddress:transaction:)
    func contactThread(for address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> TSContactThread? {
        switch transaction.readTransaction {
        case .grdbRead(let transaction):
            return grdbAdapter.contactThread(for: address, transaction: transaction)
        case .yapRead(let transaction):
            return yapdbAdapter.fetchOne(for: address, transaction: transaction)
        }
    }
}

@objc
class GRDBContactThreadFinder: NSObject {
    func contactThread(for address: SignalServiceAddress, transaction: GRDBReadTransaction) -> TSContactThread? {
        if let thread = contactThreadForUUID(address.uuid, transaction: transaction) {
            return thread
        } else if let thread = contactThreadForPhoneNumber(address.phoneNumber, transaction: transaction) {
            return thread
        } else {
            return nil
        }
    }

    private func contactThreadForUUID(_ uuid: UUID?, transaction: GRDBReadTransaction) -> TSContactThread? {
        guard let uuidString = uuid?.uuidString else { return nil }
        let sql = "SELECT * FROM \(ThreadRecord.databaseTableName) WHERE \(threadColumn: .contactUUID) = ?"
        return TSContactThread.grdbFetchOne(sql: sql, arguments: [uuidString], transaction: transaction) as? TSContactThread
    }

    private func contactThreadForPhoneNumber(_ phoneNumber: String?, transaction: GRDBReadTransaction) -> TSContactThread? {
        guard let phoneNumber = phoneNumber else { return nil }
        let sql = "SELECT * FROM \(ThreadRecord.databaseTableName) WHERE \(threadColumn: .contactPhoneNumber) = ?"
        return TSContactThread.grdbFetchOne(sql: sql, arguments: [phoneNumber], transaction: transaction) as? TSContactThread
    }
}
