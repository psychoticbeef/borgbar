import Foundation

@objc protocol PrivilegedHelperXPCProtocol {
    func runCommand(
        executable: String,
        arguments: [String],
        timeoutSeconds: Double,
        withReply reply: @escaping (Int, String, String) -> Void
    )
}

enum PrivilegedHelperConstants {
    static let serviceName = "com.da.borgbar.helper"
}
