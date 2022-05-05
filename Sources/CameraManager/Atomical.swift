//
//  Atomical.swift
//
//
//  Created by Emil Rakhmangulov on 05.05.2022.
//

import Foundation

@propertyWrapper
struct Atomical<Value> {
    private let queue = DispatchQueue(label: "atomicalQueue")
    private var value: Value

    init(wrappedValue: Value) {
        self.value = wrappedValue
    }
    
    var wrappedValue: Value {
        get {
            return queue.sync { value }
        }
        set {
            queue.sync { value = newValue }
        }
    }
}
