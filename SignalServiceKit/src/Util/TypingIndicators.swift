//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc(OWSTypingIndicators)
public protocol TypingIndicators: class {
    @objc
    var keyValueStore: SDSKeyValueStore { get }

    @objc
    func didStartTypingOutgoingInput(inThread thread: TSThread)

    @objc
    func didStopTypingOutgoingInput(inThread thread: TSThread)

    @objc
    func didSendOutgoingMessage(inThread thread: TSThread)

    @objc
    func didReceiveTypingStartedMessage(inThread thread: TSThread, address: SignalServiceAddress, deviceId: UInt)

    @objc
    func didReceiveTypingStoppedMessage(inThread thread: TSThread, address: SignalServiceAddress, deviceId: UInt)

    @objc
    func didReceiveIncomingMessage(inThread thread: TSThread, address: SignalServiceAddress, deviceId: UInt)

    // Returns the address of the user who should currently be shown typing for a given thread.
    //
    // If no one is typing in that thread, returns nil.
    // If multiple users are typing in that thread, returns the user to show.
    //
    // TODO: Use this method.
    @objc
    func typingAddress(forThread thread: TSThread) -> SignalServiceAddress?

    @objc
    func setTypingIndicatorsEnabledAndSendSyncMessage(value: Bool)

    @objc
    func setTypingIndicatorsEnabled(value: Bool, transaction: SDSAnyWriteTransaction)

    @objc
    func areTypingIndicatorsEnabled() -> Bool
}

// MARK: -

@objc(OWSTypingIndicatorsImpl)
public class TypingIndicatorsImpl: NSObject, TypingIndicators {

    // MARK: - Dependencies

    private var databaseStorage: SDSDatabaseStorage {
        return SDSDatabaseStorage.shared
    }

    // MARK: -

    @objc
    public static let typingIndicatorStateDidChange = Notification.Name("typingIndicatorStateDidChange")

    private let kDatabaseKey_TypingIndicatorsEnabled = "kDatabaseKey_TypingIndicatorsEnabled"

    private var _areTypingIndicatorsEnabled = false

    @objc
    public let keyValueStore = SDSKeyValueStore(collection: "TypingIndicators")

    private let serialQueue = DispatchQueue(label: "org.signal.typingIndicators")

    public override init() {
        super.init()

        AppReadiness.runNowOrWhenAppWillBecomeReady {
            self.setup()
        }
    }

    private func setup() {
        AssertIsOnMainThread()

        databaseStorage.read { transaction in
            self.warmCache(transaction: transaction)
        }
    }

    private func warmCache(transaction: SDSAnyReadTransaction) {
        AssertIsOnMainThread()

        let enabled = keyValueStore.getBool(kDatabaseKey_TypingIndicatorsEnabled,
                                                                defaultValue: true,
                                                                transaction: transaction)

        serialQueue.sync {
            _areTypingIndicatorsEnabled = enabled
        }
    }

    // MARK: - Dependencies

    private var syncManager: SyncManagerProtocol {
        return SSKEnvironment.shared.syncManager
    }

    // MARK: -

    @objc
    public func setTypingIndicatorsEnabledAndSendSyncMessage(value: Bool) {
        serialQueue.sync {
            Logger.info("\(_areTypingIndicatorsEnabled) -> \(value)")
            _areTypingIndicatorsEnabled = value
        }

        databaseStorage.write { transaction in
            self.keyValueStore.setBool(value,
                                       key: self.kDatabaseKey_TypingIndicatorsEnabled,
                                       transaction: transaction)
        }

        syncManager.sendConfigurationSyncMessage()

        NotificationCenter.default.postNotificationNameAsync(TypingIndicatorsImpl.typingIndicatorStateDidChange, object: nil)
    }

    @objc
    public func setTypingIndicatorsEnabled(value: Bool, transaction: SDSAnyWriteTransaction) {
        serialQueue.sync {
            Logger.info("\(_areTypingIndicatorsEnabled) -> \(value)")
            _areTypingIndicatorsEnabled = value
        }

        keyValueStore.setBool(value,
                              key: kDatabaseKey_TypingIndicatorsEnabled,
                              transaction: transaction)

        NotificationCenter.default.postNotificationNameAsync(TypingIndicatorsImpl.typingIndicatorStateDidChange, object: nil)
    }

    @objc
    public func areTypingIndicatorsEnabled() -> Bool {
        AssertIsOnMainThread()

        return serialQueue.sync { _areTypingIndicatorsEnabled }
    }

    // MARK: -

    @objc
    public func didStartTypingOutgoingInput(inThread thread: TSThread) {
        AssertIsOnMainThread()
        guard let outgoingIndicators = ensureOutgoingIndicators(forThread: thread) else {
            owsFailDebug("Could not locate outgoing indicators state")
            return
        }
        outgoingIndicators.didStartTypingOutgoingInput()
    }

    @objc
    public func didStopTypingOutgoingInput(inThread thread: TSThread) {
        AssertIsOnMainThread()
        guard let outgoingIndicators = ensureOutgoingIndicators(forThread: thread) else {
            owsFailDebug("Could not locate outgoing indicators state")
            return
        }
        outgoingIndicators.didStopTypingOutgoingInput()
    }

    @objc
    public func didSendOutgoingMessage(inThread thread: TSThread) {
        AssertIsOnMainThread()
        guard let outgoingIndicators = ensureOutgoingIndicators(forThread: thread) else {
            owsFailDebug("Could not locate outgoing indicators state")
            return
        }
        outgoingIndicators.didSendOutgoingMessage()
    }

    @objc
    public func didReceiveTypingStartedMessage(inThread thread: TSThread, address: SignalServiceAddress, deviceId: UInt) {
        AssertIsOnMainThread()
        Logger.info("")
        let incomingIndicators = ensureIncomingIndicators(forThread: thread, address: address, deviceId: deviceId)
        incomingIndicators.didReceiveTypingStartedMessage()
    }

    @objc
    public func didReceiveTypingStoppedMessage(inThread thread: TSThread, address: SignalServiceAddress, deviceId: UInt) {
        AssertIsOnMainThread()
        Logger.info("")
        let incomingIndicators = ensureIncomingIndicators(forThread: thread, address: address, deviceId: deviceId)
        incomingIndicators.didReceiveTypingStoppedMessage()
    }

    @objc
    public func didReceiveIncomingMessage(inThread thread: TSThread, address: SignalServiceAddress, deviceId: UInt) {
        AssertIsOnMainThread()
        Logger.info("")
        let incomingIndicators = ensureIncomingIndicators(forThread: thread, address: address, deviceId: deviceId)
        incomingIndicators.didReceiveIncomingMessage()
    }

    @objc
    public func typingAddress(forThread thread: TSThread) -> SignalServiceAddress? {
        AssertIsOnMainThread()

        guard areTypingIndicatorsEnabled() else {
            return nil
        }

        var firstAddress: SignalServiceAddress?
        var firstTimestamp: UInt64?

        let threadKey = incomingIndicatorsKey(forThread: thread)
        guard let deviceMap = incomingIndicatorsMap[threadKey] else {
            // No devices are typing in this thread.
            return nil
        }
        for incomingIndicators in deviceMap.values {
            guard incomingIndicators.isTyping else {
                continue
            }
            guard let startedTypingTimestamp = incomingIndicators.startedTypingTimestamp else {
                owsFailDebug("Typing device is missing start timestamp.")
                continue
            }
            if let firstTimestamp = firstTimestamp,
                firstTimestamp < startedTypingTimestamp {
                // More than one recipient/device is typing in this conversation;
                // prefer the one that started typing first.
                continue
            }
            firstAddress = incomingIndicators.address
            firstTimestamp = startedTypingTimestamp
        }
        return firstAddress
    }

    // MARK: -

    // Map of thread id-to-OutgoingIndicators.
    private var outgoingIndicatorsMap = [String: OutgoingIndicators]()

    private func ensureOutgoingIndicators(forThread thread: TSThread) -> OutgoingIndicators? {
        AssertIsOnMainThread()

        if let outgoingIndicators = outgoingIndicatorsMap[thread.uniqueId] {
            return outgoingIndicators
        }
        let outgoingIndicators = OutgoingIndicators(delegate: self, thread: thread)
        outgoingIndicatorsMap[thread.uniqueId] = outgoingIndicators
        return outgoingIndicators
    }

    // The sender maintains two timers per chat:
    //
    // A sendPause timer
    // A sendRefresh timer
    private class OutgoingIndicators {
        private weak var delegate: TypingIndicators?
        private let thread: TSThread
        private var sendPauseTimer: Timer?
        private var sendRefreshTimer: Timer?

        init(delegate: TypingIndicators, thread: TSThread) {
            self.delegate = delegate
            self.thread = thread
        }

        // MARK: - Dependencies

        private var messageSender: MessageSender {
            return SSKEnvironment.shared.messageSender
        }

        // MARK: -

        func didStartTypingOutgoingInput() {
            AssertIsOnMainThread()

            if sendRefreshTimer == nil {
                // If the user types a character into the compose box, and the sendRefresh timer isn’t running:

                sendTypingMessageIfNecessary(forThread: thread, action: .started)

                sendRefreshTimer?.invalidate()
                sendRefreshTimer = Timer.weakScheduledTimer(withTimeInterval: 10,
                                                            target: self,
                                                            selector: #selector(OutgoingIndicators.sendRefreshTimerDidFire),
                                                            userInfo: nil,
                                                            repeats: false)
            } else {
                // If the user types a character into the compose box, and the sendRefresh timer is running:
            }

            sendPauseTimer?.invalidate()
            sendPauseTimer = Timer.weakScheduledTimer(withTimeInterval: 3,
                                                      target: self,
                                                      selector: #selector(OutgoingIndicators.sendPauseTimerDidFire),
                                                      userInfo: nil,
                                                      repeats: false)
        }

        func didStopTypingOutgoingInput() {
            AssertIsOnMainThread()

            sendTypingMessageIfNecessary(forThread: thread, action: .stopped)

            sendRefreshTimer?.invalidate()
            sendRefreshTimer = nil

            sendPauseTimer?.invalidate()
            sendPauseTimer = nil
        }

        @objc
        func sendPauseTimerDidFire() {
            AssertIsOnMainThread()

            sendTypingMessageIfNecessary(forThread: thread, action: .stopped)

            sendRefreshTimer?.invalidate()
            sendRefreshTimer = nil

            sendPauseTimer?.invalidate()
            sendPauseTimer = nil
        }

        @objc
        func sendRefreshTimerDidFire() {
            AssertIsOnMainThread()

            sendTypingMessageIfNecessary(forThread: thread, action: .started)

            sendRefreshTimer?.invalidate()
            sendRefreshTimer = Timer.weakScheduledTimer(withTimeInterval: 10,
                                                        target: self,
                                                        selector: #selector(sendRefreshTimerDidFire),
                                                        userInfo: nil,
                                                        repeats: false)
        }

        func didSendOutgoingMessage() {
            AssertIsOnMainThread()

            sendRefreshTimer?.invalidate()
            sendRefreshTimer = nil

            sendPauseTimer?.invalidate()
            sendPauseTimer = nil
        }

        private func sendTypingMessageIfNecessary(forThread thread: TSThread, action: TypingIndicatorAction) {
            Logger.verbose("\(TypingIndicatorMessage.string(forTypingIndicatorAction: action))")

            guard let delegate = delegate else {
                owsFailDebug("Missing delegate.")
                return
            }
            // `areTypingIndicatorsEnabled` reflects the user-facing setting in the app preferences.
            // If it's disabled we don't want to emit "typing indicator" messages
            // or show typing indicators for other users.
            guard delegate.areTypingIndicatorsEnabled() else {
                return
            }

            let message = TypingIndicatorMessage(thread: thread, action: action)
            messageSender.sendMessage(.promise, message.asPreparer).retainUntilComplete()
        }
    }

    // MARK: -

    // Map of (thread id)-to-(recipient id and device id)-to-IncomingIndicators.
    private var incomingIndicatorsMap = [String: [AddressWithDeviceId: IncomingIndicators]]()
    private struct AddressWithDeviceId: Hashable {
        let address: SignalServiceAddress
        let deviceId: UInt
    }

    private func incomingIndicatorsKey(forThread thread: TSThread) -> String {
        return String(describing: thread.uniqueId)
    }

    private func incomingIndicatorsKey(address: SignalServiceAddress, deviceId: UInt) -> AddressWithDeviceId {
        return AddressWithDeviceId(address: address, deviceId: deviceId)
    }

    private func ensureIncomingIndicators(forThread thread: TSThread, address: SignalServiceAddress, deviceId: UInt) -> IncomingIndicators {
        AssertIsOnMainThread()

        let threadKey = incomingIndicatorsKey(forThread: thread)
        let deviceKey = incomingIndicatorsKey(address: address, deviceId: deviceId)
        guard let deviceMap = incomingIndicatorsMap[threadKey] else {
            let incomingIndicators = IncomingIndicators(delegate: self, thread: thread, address: address, deviceId: deviceId)
            incomingIndicatorsMap[threadKey] = [deviceKey: incomingIndicators]
            return incomingIndicators
        }
        guard let incomingIndicators = deviceMap[deviceKey] else {
            let incomingIndicators = IncomingIndicators(delegate: self, thread: thread, address: address, deviceId: deviceId)
            var deviceMapCopy = deviceMap
            deviceMapCopy[deviceKey] = incomingIndicators
            incomingIndicatorsMap[threadKey] = deviceMapCopy
            return incomingIndicators
        }
        return incomingIndicators
    }

    // The receiver maintains one timer for each (sender, device) in a chat:
    private class IncomingIndicators {
        private weak var delegate: TypingIndicators?
        private let thread: TSThread
        fileprivate let address: SignalServiceAddress
        private let deviceId: UInt
        private var displayTypingTimer: Timer?
        fileprivate var startedTypingTimestamp: UInt64?

        var isTyping = false {
            didSet {
                AssertIsOnMainThread()

                let didChange = oldValue != isTyping
                if didChange {
                    Logger.debug("isTyping changed: \(oldValue) -> \(self.isTyping)")

                    notifyIfNecessary()
                }
            }
        }

        init(delegate: TypingIndicators, thread: TSThread,
             address: SignalServiceAddress, deviceId: UInt) {
            self.delegate = delegate
            self.thread = thread
            self.address = address
            self.deviceId = deviceId
        }

        func didReceiveTypingStartedMessage() {
            AssertIsOnMainThread()

            displayTypingTimer?.invalidate()
            displayTypingTimer = Timer.weakScheduledTimer(withTimeInterval: 15,
                                                          target: self,
                                                          selector: #selector(IncomingIndicators.displayTypingTimerDidFire),
                                                          userInfo: nil,
                                                          repeats: false)
            if !isTyping {
                startedTypingTimestamp = NSDate.ows_millisecondTimeStamp()
            }
            isTyping = true
        }

        func didReceiveTypingStoppedMessage() {
            AssertIsOnMainThread()

            clearTyping()
        }

        @objc
        func displayTypingTimerDidFire() {
            AssertIsOnMainThread()

            clearTyping()
        }

        func didReceiveIncomingMessage() {
            AssertIsOnMainThread()

            clearTyping()
        }

        private func clearTyping() {
            AssertIsOnMainThread()

            displayTypingTimer?.invalidate()
            displayTypingTimer = nil
            startedTypingTimestamp = nil
            isTyping = false
        }

        private func notifyIfNecessary() {
            Logger.verbose("")

            guard let delegate = delegate else {
                owsFailDebug("Missing delegate.")
                return
            }
            // `areTypingIndicatorsEnabled` reflects the user-facing setting in the app preferences.
            // If it's disabled we don't want to emit "typing indicator" messages
            // or show typing indicators for other users.
            guard delegate.areTypingIndicatorsEnabled() else {
                return
            }
            NotificationCenter.default.postNotificationNameAsync(TypingIndicatorsImpl.typingIndicatorStateDidChange, object: thread.uniqueId)
        }
    }
}
