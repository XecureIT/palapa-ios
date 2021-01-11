//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import XCTest
import SignalServiceKit

class SDSPerformanceTest: PerformanceBaseTest {

    // MARK: - Insert Messages

    func testYDBPerf_insertMessages() {
        storageCoordinator.useYDBForTests()
        measureMetrics(XCTestCase.defaultPerformanceMetrics, automaticallyStartMeasuring: false) {
            insertMessages()
        }
    }

    func testGRDBPerf_insertMessages() {
        storageCoordinator.useGRDBForTests()
        measureMetrics(XCTestCase.defaultPerformanceMetrics, automaticallyStartMeasuring: false) {
            insertMessages()
        }
    }

    func insertMessages() {
        let contactThread = ContactThreadFactory().create()

        read { transaction in
            XCTAssertEqual(1, TSThread.anyFetchAll(transaction: transaction).count)
            XCTAssertEqual(0, TSInteraction.anyFetchAll(transaction: transaction).count)
        }

        let messageCount = 100
        var uniqueIds = [String]()

        let messageFactory = OutgoingMessageFactory()
        messageFactory.threadCreator = { _ in return contactThread }

        startMeasuring()
        write { transaction in
            for _ in 0..<messageCount {
                let message = messageFactory.build(transaction: transaction)
                message.anyInsert(transaction: transaction)
                uniqueIds.append(message.uniqueId)
            }
        }
        stopMeasuring()

        read { transaction in
            XCTAssertEqual(1, TSThread.anyFetchAll(transaction: transaction).count)
            XCTAssertEqual(messageCount, TSInteraction.anyFetchAll(transaction: transaction).count)
        }

        // cleanup for next iteration
        write { transaction in
            contactThread.anyRemove(transaction: transaction)
        }
    }

    // MARK: - Fetch Messages

    func testYDBPerf_fetchMessages() {
        storageCoordinator.useYDBForTests()
        measureMetrics(XCTestCase.defaultPerformanceMetrics, automaticallyStartMeasuring: false) {
            fetchMessages()
        }
    }

    func testGRDBPerf_fetchMessages() {
        storageCoordinator.useGRDBForTests()
        measureMetrics(XCTestCase.defaultPerformanceMetrics, automaticallyStartMeasuring: false) {
            fetchMessages()
        }
    }

    func fetchMessages() {
        let messageCount = 100
        let fetchCount = messageCount * 5

        var uniqueIds = [String]()
        write { transaction in
            XCTAssert(TSInteraction.anyCount(transaction: transaction) == 0)

            for _ in 0..<messageCount {
                let message = OutgoingMessageFactory().create(transaction: transaction)
                uniqueIds.append(message.uniqueId)
            }
        }

        startMeasuring()
        read { transaction in
            for _ in 0..<fetchCount {
                let message = TSOutgoingMessage.anyFetch(uniqueId: uniqueIds.randomElement()!, transaction: transaction)
                XCTAssertNotNil(message)
            }
        }
        stopMeasuring()

        // cleanup for next iteration
        write { transaction in
            TSThread.anyRemoveAllWithInstantation(transaction: transaction)
            TSInteraction.anyRemoveAllWithInstantation(transaction: transaction)
        }
    }

    // MARK: - Enumerate Messages

    func testYDBPerf_enumerateMessagesUnbatched() {
        storageCoordinator.useYDBForTests()
        measureMetrics(XCTestCase.defaultPerformanceMetrics, automaticallyStartMeasuring: false) {
            enumerateMessages(batched: false)
        }
    }

    func testGRDBPerf_enumerateMessagesUnbatched() {
        storageCoordinator.useGRDBForTests()
        measureMetrics(XCTestCase.defaultPerformanceMetrics, automaticallyStartMeasuring: false) {
            enumerateMessages(batched: false)
        }
    }

    func testYDBPerf_enumerateMessagesBatched() {
        storageCoordinator.useYDBForTests()
        measureMetrics(XCTestCase.defaultPerformanceMetrics, automaticallyStartMeasuring: false) {
            enumerateMessages(batched: true)
        }
    }

    func testGRDBPerf_enumerateMessagesBatched() {
        storageCoordinator.useGRDBForTests()
        measureMetrics(XCTestCase.defaultPerformanceMetrics, automaticallyStartMeasuring: false) {
            enumerateMessages(batched: true)
        }
    }

    func enumerateMessages(batched: Bool) {
        let messageCount = 100
        let enumerationCount = 10

        var uniqueIds = [String]()
        write { transaction in
            XCTAssert(TSInteraction.anyCount(transaction: transaction) == 0)

            for _ in 0..<messageCount {
                let message = OutgoingMessageFactory().create(transaction: transaction)
                uniqueIds.append(message.uniqueId)
            }
        }

        startMeasuring()
        read { transaction in
            var enumeratedCount = 0
            for _ in 0..<enumerationCount {
                TSInteraction.anyEnumerate(transaction: transaction, batched: batched) { _, _ in
                    enumeratedCount += 1
                }
            }
            XCTAssertEqual(enumeratedCount, messageCount * enumerationCount)
        }
        stopMeasuring()

        // cleanup for next iteration
        write { transaction in
            TSThread.anyRemoveAllWithInstantation(transaction: transaction)
            TSInteraction.anyRemoveAllWithInstantation(transaction: transaction)
        }
    }

    private func buildEnvelope(for thread: TSThread) -> SSKProtoEnvelope {
        let source: SignalServiceAddress
        switch thread {
        case let groupThread as TSGroupThread:
            source = groupThread.groupModel.groupMembers[0]
        case let contactThread as TSContactThread:
            source = contactThread.contactAddress
        default:
            owsFail("Invalid thread.")
        }

        let timestamp = NSDate.ows_millisecondTimeStamp()
        let envelopeBuilder = SSKProtoEnvelope.builder(timestamp: timestamp)
        envelopeBuilder.setType(.ciphertext)
        if let phoneNumber = source.phoneNumber {
            envelopeBuilder.setSourceE164(phoneNumber)
        }
        if let uuid = source.uuid {
            envelopeBuilder.setSourceUuid(uuid.uuidString)
        }
        envelopeBuilder.setSourceDevice(1)
        return try! envelopeBuilder.build()
    }
}
