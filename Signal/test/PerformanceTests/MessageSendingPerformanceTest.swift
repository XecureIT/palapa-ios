//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import XCTest
//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import XCTest
@testable import SignalServiceKit
import GRDB

class MessageSendingPerformanceTest: PerformanceBaseTest {

    // MARK: -

    let stubbableNetworkManager = StubbableNetworkManager(default: ())

    var dbObserverBlock: (() -> Void)?
    private var dbObserver: BlockObserver?

    let localE164Identifier = "+13235551234"
    let localUUID = UUID()

    let localClient = LocalSignalClient()
    let runner = TestProtocolRunner()

    // MARK: - Dependencies

    var tsAccountManager: TSAccountManager {
        return SSKEnvironment.shared.tsAccountManager
    }

    var identityManager: OWSIdentityManager {
        return SSKEnvironment.shared.identityManager
    }

    // MARK: - Hooks

    override func setUp() {
        super.setUp()
        MockSSKEnvironment.shared.networkManager = self.stubbableNetworkManager

        // use the *real* message sender to measure it's perf
        MockSSKEnvironment.shared.messageSender = MessageSender()
        MockSSKEnvironment.shared.messageSenderJobQueue.setup()

        // Observe DB changes so we can know when all the async processing is done
        let dbObserver = BlockObserver(block: { self.dbObserverBlock?() })
        self.dbObserver = dbObserver
        databaseStorage.add(databaseStorageObserver: dbObserver)
    }

    override func tearDown() {
        dbObserver = nil
        super.tearDown()
    }

    // MARK: -

    func testYapDBPerf_messageSending_contactThread() {
        storageCoordinator.useYDBForTests()
        measureMetrics(XCTestCase.defaultPerformanceMetrics, automaticallyStartMeasuring: false) {
            sendMessages_contactThread()
        }
    }

    func testGRDBPerf_messageSending_contactThread() {
        // This is an example of a performance test case.
        storageCoordinator.useGRDBForTests()
        try! databaseStorage.grdbStorage.setupUIDatabase()
        measureMetrics(XCTestCase.defaultPerformanceMetrics, automaticallyStartMeasuring: false) {
            sendMessages_contactThread()
        }
        databaseStorage.grdbStorage.testing_tearDownUIDatabase()
    }

    func testYapDBPerf_messageSending_groupThread() {
        storageCoordinator.useYDBForTests()
        measureMetrics(XCTestCase.defaultPerformanceMetrics, automaticallyStartMeasuring: false) {
            sendMessages_groupThread()
        }
    }

    func testGRDBPerf_messageSending_groupThread() {
        // This is an example of a performance test case.
        storageCoordinator.useGRDBForTests()
        try! databaseStorage.grdbStorage.setupUIDatabase()
        measureMetrics(XCTestCase.defaultPerformanceMetrics, automaticallyStartMeasuring: false) {
            sendMessages_groupThread()
        }
        databaseStorage.grdbStorage.testing_tearDownUIDatabase()
    }

    func sendMessages_groupThread() {
        // ensure local client has necessary "registered" state
        identityManager.generateNewIdentityKey()
        tsAccountManager.registerForTests(withLocalNumber: localE164Identifier, uuid: localUUID)

        // Session setup
        let groupMemberClients: [FakeSignalClient] = (0..<5).map { _ in
            return FakeSignalClient.generate(e164Identifier: CommonGenerator.e164())
        }

        for client in groupMemberClients {
            write { transaction in
                try! self.runner.initialize(senderClient: self.localClient,
                                            recipientClient: client,
                                            transaction: transaction)
            }
        }

        let threadFactory = GroupThreadFactory()
        threadFactory.memberAddressesBuilder = {
            groupMemberClients.map { $0.address }
        }

        let thread: TSGroupThread = databaseStorage.write { transaction in
            XCTAssertEqual(0, TSMessage.anyCount(transaction: transaction))
            XCTAssertEqual(0, TSThread.anyCount(transaction: transaction))
            return threadFactory.create(transaction: transaction)
        }

        sendMessages(thread: thread)
    }

    func sendMessages_contactThread() {
        // ensure local client has necessary "registered" state
        identityManager.generateNewIdentityKey()
        tsAccountManager.registerForTests(withLocalNumber: localE164Identifier, uuid: localUUID)

        // Session setup
        let bobClient = FakeSignalClient.generate(e164Identifier: "+18083235555")

        write { transaction in
            XCTAssertEqual(0, TSMessage.anyCount(transaction: transaction))
            XCTAssertEqual(0, TSThread.anyCount(transaction: transaction))

            try! self.runner.initialize(senderClient: self.localClient,
                                        recipientClient: bobClient,
                                        transaction: transaction)
        }

        let threadFactory = ContactThreadFactory()
        threadFactory.contactAddressBuilder = { bobClient.address }
        let thread = threadFactory.create()

        sendMessages(thread: thread)
    }

    func sendMessages(thread: TSThread) {
        let totalNumberToSend = 50
        let expectMessagesSent = expectation(description: "messages sent")
        var hasFulfilled = false
        let fulfillOnce = {
            if !hasFulfilled {
                hasFulfilled = true
                expectMessagesSent.fulfill()
            }
        }

        self.dbObserverBlock = {
            let (messageCount, attemptingOutCount): (UInt, Int) = self.databaseStorage.read { transaction in
                let messageCount = TSInteraction.anyCount(transaction: transaction)
                let attemptingOutCount = InteractionFinder.attemptingOutInteractionIds(transaction: transaction).count
                return (messageCount, attemptingOutCount)
            }

            if (messageCount == totalNumberToSend && attemptingOutCount == 0) {
                fulfillOnce()
            }
        }

        startMeasuring()

        for _ in (0..<totalNumberToSend) {
            // Each is intentionally in a separate transaction, to be closer to the app experience
            // of sending each message
            self.read { transaction in
                ThreadUtil.enqueueMessage(withText: CommonGenerator.paragraph,
                                          in: thread,
                                          quotedReplyModel: nil,
                                          linkPreviewDraft: nil,
                                          transaction: transaction)
            }
        }

        waitForExpectations(timeout: 20.0) { _ in
            self.stopMeasuring()

            self.dbObserverBlock = nil
            // There's some async stuff that happens in message sender that will explode if
            // we delete these models too early - e.g. sending a sync message, which we can't
            // easily wait for in an explicit way.
            sleep(1)
            self.write { transaction in
                TSInteraction.anyRemoveAllWithInstantation(transaction: transaction)
                TSThread.anyRemoveAllWithInstantation(transaction: transaction)
                SSKMessageSenderJobRecord.anyRemoveAllWithInstantation(transaction: transaction)
                OWSRecipientIdentity.anyRemoveAllWithInstantation(transaction: transaction)
            }
        }
    }
}

private class BlockObserver: SDSDatabaseStorageObserver {
    let block: () -> Void
    init(block: @escaping () -> Void) {
        self.block = block
    }

    func databaseStorageDidUpdate(change: SDSDatabaseStorageChange) {
        block()
    }

    func databaseStorageDidUpdateExternally() {
        block()
    }

    func databaseStorageDidReset() {
        block()
    }
}

class StubbableNetworkManager: TSNetworkManager {
    var block: (TSRequest, TSNetworkManagerSuccess, TSNetworkManagerFailure) -> Void = { request, success, failure in
        let fakeTask = URLSessionDataTask()
        Logger.info("faking success for request: \(request)")
        success(fakeTask, nil)
    }

    override func makeRequest(_ request: TSRequest, completionQueue: DispatchQueue, success: @escaping TSNetworkManagerSuccess, failure: @escaping TSNetworkManagerFailure) {

        // This latency is optimistic because I didn't want to slow
        // the tests down too much. But I did want to introduce some
        // non-trivial latency to make any interactions with the various
        // async's a little more realistic.
        let fakeNetworkLatency = DispatchTimeInterval.milliseconds(25)
        completionQueue.asyncAfter(deadline: .now() + fakeNetworkLatency) {
            self.block(request, success, failure)
        }
    }
}
