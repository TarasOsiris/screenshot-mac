//
//  Item.swift
//  screenshot
//
//  Created by Taras Leskiv on 05.03.2026.
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
