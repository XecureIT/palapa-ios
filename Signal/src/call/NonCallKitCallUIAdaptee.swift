//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit
import SignalMessaging

/**
 * Manage call related UI in a pre-CallKit world.
 */
class NonCallKitCallUIAdaptee: NSObject, CallUIAdaptee {

    let notificationPresenter: NotificationPresenter
    let callService: CallService

    // Starting/Stopping incoming call ringing is our apps responsibility for the non CallKit interface.
    let hasManualRinger = true

    required init(callService: CallService, notificationPresenter: NotificationPresenter) {
        AssertIsOnMainThread()

        self.callService = callService
        self.notificationPresenter = notificationPresenter

        super.init()
    }

    // MARK: Dependencies

    var audioSession: OWSAudioSession {
        return Environment.shared.audioSession
    }

    // MARK: 

    func startOutgoingCall(handle: SignalServiceAddress) -> SignalCall {
        AssertIsOnMainThread()

        let call = SignalCall.outgoingCall(localId: UUID(), remoteAddress: handle)

        // make sure we don't terminate audio session during call
        let success = self.audioSession.startAudioActivity(call.audioActivity)
        assert(success)

        self.callService.handleOutgoingCall(call).retainUntilComplete()

        return call
    }

    func reportIncomingCall(_ call: SignalCall, callerName: String) {
        AssertIsOnMainThread()

        Logger.debug("")

        self.showCall(call)

        // present lock screen notification
        if UIApplication.shared.applicationState == .active {
            Logger.debug("skipping notification since app is already active.")
        } else {
            notificationPresenter.presentIncomingCall(call, callerName: callerName)
        }
    }

    func reportMissedCall(_ call: SignalCall, callerName: String) {
        AssertIsOnMainThread()

        notificationPresenter.presentMissedCall(call, callerName: callerName)
    }

    func answerCall(localId: UUID) {
        AssertIsOnMainThread()

        guard let call = self.callService.currentCall else {
            owsFailDebug("No current call.")
            return
        }

        guard call.localId == localId else {
            owsFailDebug("localId does not match current call")
            return
        }

        self.answerCall(call)
    }

    func answerCall(_ call: SignalCall) {
        AssertIsOnMainThread()

        guard call.localId == self.callService.currentCall?.localId else {
            owsFailDebug("localId does not match current call")
            return
        }

        self.audioSession.isRTCAudioEnabled = true
        self.callService.handleAnswerCall(call)
    }

    func recipientAcceptedCall(_ call: SignalCall) {
        AssertIsOnMainThread()

        self.audioSession.isRTCAudioEnabled = true
    }

    func localHangupCall(localId: UUID) {
        AssertIsOnMainThread()

        guard let call = self.callService.currentCall else {
            owsFailDebug("No current call.")
            return
        }

        guard call.localId == localId else {
            owsFailDebug("localId does not match current call")
            return
        }

        self.localHangupCall(call)
    }

    func localHangupCall(_ call: SignalCall) {
        AssertIsOnMainThread()

        // If both parties hang up at the same moment,
        // call might already be nil.
        guard self.callService.currentCall == nil || call.localId == self.callService.currentCall?.localId else {
            owsFailDebug("localId does not match current call")
            return
        }

        self.callService.handleLocalHungupCall(call)
    }

    internal func remoteDidHangupCall(_ call: SignalCall) {
        AssertIsOnMainThread()

        Logger.debug("is no-op")
    }

    internal func remoteBusy(_ call: SignalCall) {
        AssertIsOnMainThread()

        Logger.debug("is no-op")
    }

    internal func failCall(_ call: SignalCall, error: CallError) {
        AssertIsOnMainThread()

        Logger.debug("is no-op")
    }

    func setIsMuted(call: SignalCall, isMuted: Bool) {
        AssertIsOnMainThread()

        guard call.localId == self.callService.currentCall?.localId else {
            owsFailDebug("localId does not match current call")
            return
        }

        self.callService.setIsMuted(call: call, isMuted: isMuted)
    }

    func setHasLocalVideo(call: SignalCall, hasLocalVideo: Bool) {
        AssertIsOnMainThread()

        guard call.localId == self.callService.currentCall?.localId else {
            owsFailDebug("localId does not match current call")
            return
        }

        self.callService.setHasLocalVideo(hasLocalVideo: hasLocalVideo)
    }
}
