//
//  Item.swift
//  Compass Gate FTP
//
//  Created by Bobby Rinaldo Sukma Dewa on 10/10/26.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
