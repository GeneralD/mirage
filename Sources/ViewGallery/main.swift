import AppKit
import Foundation

let outcome = GalleryCommand(screens: galleryScreens).run(
    arguments: Array(CommandLine.arguments.dropFirst()),
    output: { FileHandle.standardOutput.write(Data(($0 + "\n").utf8)) },
    errorOutput: { FileHandle.standardError.write(Data(($0 + "\n").utf8)) })

switch outcome {
case .exit(let status):
    exit(status)
case .launch(let screen):
    let delegate = GalleryAppDelegate(screen: screen)
    NSApplication.shared.delegate = delegate
    NSApplication.shared.setActivationPolicy(.regular)
    // `NSApplication.delegate` does not own the delegate: keep it alive for the whole run loop.
    withExtendedLifetime(delegate) {
        NSApplication.shared.run()
    }
}
