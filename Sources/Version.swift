//
//  Version.swift
//  DePublicize
//
//  Created by Vitaly Aminev on 2019-12-27.
//

import Foundation
import SPMUtility
import Basic

struct Version: Command {
  let command = "version"
  let overview = "prints current version"

  init(parser: ArgumentParser) {
    _ = parser.add(subparser: command, overview: overview)
  }

  func run(with arguments: ArgumentParser.Result) throws {
    print("0.0.0+streamlayer")
  }
}
