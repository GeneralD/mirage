private let galleryUsage = "usage: view-gallery <screen> | --list | --help"

/// What `view-gallery`'s arguments ask for, and so what the process does next. It prints through the two closures it is given and
/// never ends the process itself: `main.swift` does that, so that this stays testable.
struct GalleryCommand {
    /// What the process does next.
    enum Outcome: Equatable {
        /// Open this screen and run the application.
        case launch(GalleryScreen)
        /// End the process with this status.
        case exit(Int32)
    }

    let screens: [GalleryScreen]

    func run(arguments: [String], output: (String) -> Void, errorOutput: (String) -> Void) -> Outcome {
        guard let first = arguments.first else {
            errorOutput(galleryUsage)
            return .exit(2)
        }
        if let extra = arguments.dropFirst().first {
            errorOutput("gallery: unexpected argument \"\(extra)\"")
            return .exit(2)
        }
        switch first {
        case "--list":
            for screen in screens {
                output("\(screen.name)\t\(screen.summary)")
            }
            return .exit(0)
        case "--help", "-h":
            output(galleryUsage)
            return .exit(0)
        case _ where first.hasPrefix("-"):
            errorOutput("gallery: unexpected argument \"\(first)\"")
            return .exit(2)
        default:
            guard let screen = screens.first(where: { $0.name == first }) else {
                let names = screens.isEmpty ? "(none)" : screens.map(\.name).joined(separator: ", ")
                errorOutput("gallery: no screen named \"\(first)\"; screens: \(names)")
                return .exit(2)
            }
            return .launch(screen)
        }
    }
}
