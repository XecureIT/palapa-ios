//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public extension NSDate {
    var ows_millisecondsSince1970: UInt64 {
        return NSDate.ows_millisecondsSince1970(for: self as Date)
    }
}

public extension Date {
    var ows_millisecondsSince1970: UInt64 {
        return (self as NSDate).ows_millisecondsSince1970
    }

    static func ows_millisecondTimestamp() -> UInt64 {
        return NSDate.ows_millisecondTimeStamp()
    }
}
