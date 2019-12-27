import Foundation

var registry = CommandRegistry(usage: "<command> <options>",
                               overview: "prepends <prefix> to open/public identiffiers")
registry.register(command: Rewrite.self)
registry.register(command: Version.self)
registry.run()
