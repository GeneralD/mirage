/// What the host did at launch, in order: install (or confirm) the extension,
/// obtain camera permission, start the frame pipeline.
public struct LaunchReport: Sendable, Hashable {
    public let install: InstallStatus
    public let authorization: CameraAuthorizationStatus
    public let pipelineStarted: Bool

    public init(install: InstallStatus, authorization: CameraAuthorizationStatus, pipelineStarted: Bool) {
        self.install = install
        self.authorization = authorization
        self.pipelineStarted = pipelineStarted
    }
}
