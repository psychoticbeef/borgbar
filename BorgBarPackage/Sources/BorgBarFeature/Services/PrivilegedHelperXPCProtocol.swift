import Foundation

@objc public protocol PrivilegedHelperXPCProtocol {
    func runCommand(
        executable: String,
        arguments: [String],
        timeoutSeconds: Double,
        withReply reply: @escaping (Int, String, String) -> Void
    )
}

public enum PrivilegedHelperConstants {
    public static let serviceName = "com.da.borgbar.helper"
}
