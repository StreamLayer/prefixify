//
//  Rewrite.swift
//  DePublicize
//
//  Created by Vitaly Aminev on 2019-12-27.
//

import Foundation
import SPMUtility
import Basic
import Path

private let fileManager = FileManager.default

struct Rewrite: Command {
  let command = "rewrite"
  let overview = "rewrites public & open identifiers in a given folder"

  private let directory: PositionalArgument<String>
  private let outputDirectory: PositionalArgument<String>
  private let prefix: OptionArgument<String>
  private let report: OptionArgument<String>
  private let includes: OptionArgument<[String]>
  private let inplace: OptionArgument<Bool>

  init(parser: ArgumentParser) {
    let parser = parser.add(subparser: command, overview: overview)

    directory = parser.add(positional: "directory",
                           kind: String.self,
                           optional: false,
                           usage: "path to source files")

    outputDirectory = parser.add(positional: "output directory",
                                 kind: String.self,
                                 optional: false,
                                 usage: "spit here")

    prefix = parser.add(option: "--prefix",
                        shortName: "-p",
                        kind: String.self,
                        usage: "Prefix to use")

    report = parser.add(option: "--report",
                        shortName: "-r",
                        kind: String.self,
                        usage: "report list of changed ids")

    includes = parser.add(option: "--include",
                          shortName: "-i",
                          kind: [String].self,
                          usage: "rewrite ids from these reports")

    inplace = parser.add(option: "--in-place",
                         shortName: "-o",
                         kind: Bool.self,
                         usage: "rewrites files in-place")
  }

  func run(with arguments: ArgumentParser.Result) throws {
    let input = arguments.get(self.directory)!
    let output = arguments.get(self.outputDirectory)!
    let prefix = arguments.get(self.prefix)!
    let includes = arguments.get(self.includes)
    let inplace = arguments.get(self.inplace) ?? false

    guard let inputDir = Path(input), inputDir.isDirectory else {
      throw NSError(domain: "E_DIR_IN", code: 404, userInfo: ["path": input])
    }

    guard let outputDir = Path(output), outputDir.isDirectory else {
      throw NSError(domain: "E_DIR_OUT", code: 404, userInfo: ["path": output])
    }

    if !inplace {
      print("cleaning files in \(outputDir.description)")
      for content in outputDir.ls() {
        try content.delete()
      }
    }

    print("copying files over to \(outputDir.description)")
    for content in inputDir.ls() {
      try content.copy(into: outputDir, overwrite: inplace)
    }

    var reports = [SLRIdentifiersReport]()
    if let includes = includes {
      let decoder = JSONDecoder()
      for file in includes {
        let path = Path(file) ?? Path.cwd/file
        guard path.isReadable else {
          throw NSError(domain: "E_INC_ERR", code: 404, userInfo: ["path": file])
        }

        let contents = try Data(contentsOf: path)
        reports.append(try decoder.decode(SLRIdentifiersReport.self, from: contents))
      }
    }

    let paths = inputDir.find().extension("swift").type(.file).map { $0 }
    let urls = paths.map { $0.url }
    let processed = try rewrite(urls, prefix: prefix, reports: reports)

    for (idx, syntax) in processed.syntax.enumerated() {
      let path = paths[idx]
      let output = try path.absolutePath(relativeTo: inputDir, in: outputDir)
      var writeTo = try LocalFileOutputByteStream(output, closeOnDeinit: false, buffered: true)
      syntax.write(to: &writeTo)
      try writeTo.close()
    }

    if let identifiersReport = arguments.get(self.report) {
      let reportFile = Path(identifiersReport) ?? Path.cwd/identifiersReport
      let report = SLRIdentifiersReport(prefix: prefix,
                                        identifiers: Array(processed.identifiers),
                                        fnReplace: Array(processed.fnReplace))
      let encodedData = try JSONEncoder().encode(report)
      try encodedData.write(to: reportFile)

      print("report available at \(reportFile.description)")
    }
  }
}
