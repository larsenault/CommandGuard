//
//  Item.swift
//  CommandGuardGateway
//
//  This file is built automatically with any new Xcode project. 
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
