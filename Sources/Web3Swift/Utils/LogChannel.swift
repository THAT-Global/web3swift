//
//  LogChannel.swift
//  web3swift
//

import os

struct LogChannel {
    #if DEBUG
    let logger: Logger
    init(subsystem: String, category: String) {
        self.logger = Logger(subsystem: subsystem, category: category)
    }
    func debug(_ message: @autoclosure () -> String) { let m = message(); logger.debug("\(m)") }
    func info(_ message: @autoclosure () -> String) { let m = message(); logger.info("\(m)") }
    func warning(_ message: @autoclosure () -> String) { let m = message(); logger.warning("\(m)") }
    func error(_ message: @autoclosure () -> String) { let m = message(); logger.error("\(m)") }
    func fault(_ message: @autoclosure () -> String) { let m = message(); logger.fault("\(m)") }
    #else
    init(subsystem: String, category: String) {}
    @inline(__always) func debug(_ message: @autoclosure () -> String) {}
    @inline(__always) func info(_ message: @autoclosure () -> String) {}
    @inline(__always) func warning(_ message: @autoclosure () -> String) {}
    @inline(__always) func error(_ message: @autoclosure () -> String) {}
    @inline(__always) func fault(_ message: @autoclosure () -> String) {}
    #endif
}
