#!/usr/bin/env swift
import Foundation
import IOKit.pwr_mgt
import Darwin

struct ProbeConfig {
    var rounds: Int = 8
    var spacingSeconds: TimeInterval = 20
    var firstDelaySeconds: TimeInterval = 300
    var testTag: String = "BorgBarWakeProbe"
}

func parseArgs() -> ProbeConfig {
    var config = ProbeConfig()
    var iterator = CommandLine.arguments.dropFirst().makeIterator()
    while let arg = iterator.next() {
        switch arg {
        case "--rounds":
            if let next = iterator.next(), let value = Int(next), value > 0 {
                config.rounds = value
            }
        case "--spacing":
            if let next = iterator.next(), let value = Double(next), value >= 1 {
                config.spacingSeconds = value
            }
        case "--delay":
            if let next = iterator.next(), let value = Double(next), value >= 60 {
                config.firstDelaySeconds = value
            }
        case "--tag":
            if let next = iterator.next(), !next.isEmpty {
                config.testTag = next
            }
        default:
            break
        }
    }
    return config
}

func describe(_ result: IOReturn) -> String {
    switch result {
    case kIOReturnSuccess:
        return "kIOReturnSuccess"
    case kIOReturnNotPrivileged:
        return "kIOReturnNotPrivileged"
    case kIOReturnNotPermitted:
        return "kIOReturnNotPermitted"
    case kIOReturnNoDevice:
        return "kIOReturnNoDevice"
    default:
        return String(cString: mach_error_string(result))
    }
}

let config = parseArgs()
let start = Date().addingTimeInterval(config.firstDelaySeconds)

print("Wake probe starting")
print("rounds=\(config.rounds) spacing=\(Int(config.spacingSeconds))s delay=\(Int(config.firstDelaySeconds))s")
print("first target=\(start)")

for index in 0..<config.rounds {
    let target = start.addingTimeInterval(TimeInterval(index) * config.spacingSeconds)
    let result = IOPMSchedulePowerEvent(target as CFDate, config.testTag as CFString, kIOPMAutoWake as CFString)
    let hex = String(format: "0x%08X", UInt32(bitPattern: result))
    print("[\(index + 1)/\(config.rounds)] target=\(target) result=\(result) \(hex) \(describe(result))")
}
