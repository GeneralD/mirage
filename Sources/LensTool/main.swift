import Foundation
import HostDependencyInjection

exit(await LensToolMain().run(Array(CommandLine.arguments.dropFirst())))
