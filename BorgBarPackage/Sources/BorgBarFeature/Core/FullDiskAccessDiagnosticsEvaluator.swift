import Foundation

enum FullDiskAccessDiagnosticsEvaluator {
    static func evaluate(
        tmutilProbe: FullDiskAccessProbe,
        pathProbes: [FullDiskAccessProbe]
    ) -> FullDiskAccessDiagnostics {
        if tmutilProbe.state == .permissionDenied {
            return FullDiskAccessDiagnostics(granted: false, probes: [tmutilProbe])
        }

        let probes = [tmutilProbe] + pathProbes
        if pathProbes.contains(where: { $0.state == .permissionDenied }) {
            return FullDiskAccessDiagnostics(granted: false, probes: probes)
        }
        if pathProbes.contains(where: { $0.state == .accessible }) {
            return FullDiskAccessDiagnostics(granted: true, probes: probes)
        }

        let existingProbeCount = pathProbes.filter { $0.state != .missing }.count
        if existingProbeCount == 0 {
            // No protected targets found to validate FDA. Be conservative: avoid false positives.
            return FullDiskAccessDiagnostics(granted: false, probes: probes)
        }
        // Existing targets were present, but none were readable; treat as not granted.
        return FullDiskAccessDiagnostics(granted: false, probes: probes)
    }
}
