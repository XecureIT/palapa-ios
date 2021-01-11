//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class SignalServiceProfile: NSObject {

    public enum ValidationError: Error {
        case invalid(description: String)
        case invalidIdentityKey(description: String)
        case invalidProfileName(description: String)
    }

    public let address: SignalServiceAddress
    public let identityKey: Data
    public let profileNameEncrypted: Data?
    public let username: String?
    public let avatarUrlPath: String?
    public let unidentifiedAccessVerifier: Data?
    public let hasUnrestrictedUnidentifiedAccess: Bool
    public let supportsUUID: Bool

    public init(address: SignalServiceAddress?, responseObject: Any?) throws {
        guard let params = ParamParser(responseObject: responseObject) else {
            throw ValidationError.invalid(description: "invalid response: \(String(describing: responseObject))")
        }

        if let address = address {
            self.address = address
        } else if let uuidString: String = try params.required(key: "uuid") {
            self.address = SignalServiceAddress(uuidString: uuidString)
        } else {
            throw ValidationError.invalid(description: "response or input missing address")
        }

        let identityKeyWithType = try params.requiredBase64EncodedData(key: "identityKey")
        guard identityKeyWithType.count == kIdentityKeyLength else {
            throw ValidationError.invalidIdentityKey(description: "malformed identity key \(identityKeyWithType.hexadecimalString) with decoded length: \(identityKeyWithType.count)")
        }
        do {
            // `removeKeyType` is an objc category method only on NSData, so temporarily cast.
            self.identityKey = try (identityKeyWithType as NSData).removeKeyType() as Data
        } catch {
            // `removeKeyType` throws an SCKExceptionWrapperError, which, typically should
            // be unwrapped by any objc code calling this method.
            owsFailDebug("identify key had unexpected format")
            throw ValidationError.invalidIdentityKey(description: "malformed identity key \(identityKeyWithType.hexadecimalString) with data: \(identityKeyWithType)")
        }

        self.profileNameEncrypted = try params.optionalBase64EncodedData(key: "name")

        self.username = try params.optional(key: "username")

        let avatarUrlPath: String? = try params.optional(key: "avatar")
        self.avatarUrlPath = avatarUrlPath

        self.unidentifiedAccessVerifier = try params.optionalBase64EncodedData(key: "unidentifiedAccess")

        self.hasUnrestrictedUnidentifiedAccess = try params.optional(key: "unrestrictedUnidentifiedAccess") ?? false

        if FeatureFlags.uuidCapabilities {
            guard let capabilities = ParamParser(responseObject: try params.required(key: "capabilities")) else {
                owsFailDebug("invalid capabilities")
                throw ValidationError.invalid(description: "invalid capabilities: \(String(describing: params))")
            }
            self.supportsUUID = try capabilities.required(key: "uuid")
        } else {
            self.supportsUUID = false
        }
    }
}
