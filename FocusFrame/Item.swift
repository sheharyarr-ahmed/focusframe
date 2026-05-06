//
//  Item.swift
//  FocusFrame
//
//  Created by Sheharyar Ahmed on 07/05/2026.
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
