import Domain

/// The observation of the camera's state that `CameraMenuPresenter` keeps: the cameras and choices on
/// offer, the choices in effect, and whether the chosen camera can be used.
typealias CameraStateObservation = StateObservation<CameraState>
