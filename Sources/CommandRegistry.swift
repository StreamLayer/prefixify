//
//  CommandRegistry.swift
//  DePublicize
//
//  Created by Vitaly Aminev on 2019-12-27.
//

import Foundation
import Basic
import SPMUtility

protocol Command {
  var command: String { get }
  var overview: String { get }
  init(parser: ArgumentParser)
  func run(with arguments: ArgumentParser.Result) throws
}

private let stdout = FileHandle.standardOutput
private let stderr = FileHandle.standardError

struct CommandRegistry {
  private let parser: ArgumentParser
  private var commands: [Command] = []

  init(usage: String, overview: String) {
      parser = ArgumentParser(usage: usage, overview: overview)
  }

  mutating func register(command: Command.Type) {
    commands.append(command.init(parser: parser))
  }

  func run() {
    do {
      let parsedArguments = try parse()
      try process(arguments: parsedArguments)
    } catch let error as ArgumentParserError {
      stderr.write(error.description.data(using: .utf8)!)
    } catch let error as NSError {
      stderr.write(error.description.data(using: .utf8)!)
    } catch {
      stderr.write(error.localizedDescription.data(using: .utf8)!)
    }
  }

  private func parse() throws -> ArgumentParser.Result {
    let arguments = Array(ProcessInfo.processInfo.arguments.dropFirst())
    return try parser.parse(arguments)
  }

  private func process(arguments: ArgumentParser.Result) throws {
    guard let subparser = arguments.subparser(parser),
      let command = commands.first(where: { $0.command == subparser }) else {
      parser.printUsage(on: stdoutStream)
      return
    }
    try command.run(with: arguments)
  }
}
