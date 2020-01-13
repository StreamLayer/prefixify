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

struct Rename {
  let token: String
  let prefix: String
  
  init(raw: String) {
    let contents = raw.split(separator: ":")
    
    precondition(contents.count == 2, "rename token must be in the form of `prefix:token`")
    
    self.prefix = String(contents[0])
    self.token = String(contents[1])
  }
}

struct Rewrite: Command {
  let command = "rewrite"
  let overview = "rewrites public & open identifiers in a given folder"

  private let directory: PositionalArgument<String>
  private let outputDirectory: PositionalArgument<String>
  private let prefix: OptionArgument<String>
  private let report: OptionArgument<String>
  private let includes: OptionArgument<[String]>
  private let inplace: OptionArgument<Bool>
  private let products: OptionArgument<[String]>
  private let exclude: OptionArgument<[String]>
  private let noBase: OptionArgument<Bool>
  private let rewrites: OptionArgument<[String]>

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

    products = parser.add(option: "--product-name",
                          shortName: "-n",
                          kind: [String].self,
                          usage: "adds product names in the reports")

    exclude = parser.add(option: "--exclude",
                         shortName: "-e",
                         kind: [String].self,
                         usage: "exclude identifiers to be transformed")
    
    noBase = parser.add(option: "--reports-only",
                        kind: Bool.self,
                        usage: "rewrite only based on the reports")

    rewrites = parser.add(option: "--rewrite",
                          shortName: "-r",
                          kind: [String].self,
                          usage: "add manual token rename")
  }

  func run(with arguments: ArgumentParser.Result) throws {
    let input = arguments.get(self.directory)!
    let output = arguments.get(self.outputDirectory)!
    let prefix = arguments.get(self.prefix)!
    let includes = arguments.get(self.includes)
    let inplace = arguments.get(self.inplace) ?? false
    let exclude = arguments.get(self.exclude) ?? []
    let productNames = arguments.get(self.products) ?? []
    let noBase = arguments.get(self.noBase) ?? false
    let rewrites: [Rename] = (arguments.get(self.rewrites) ?? []).map { Rename(raw: $0) }

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

    if rewrites.count > 0 {
      reports.append(contentsOf: rewrites.map {
        SLRIdentifiersReport(prefix: "\($0.prefix)_", identifiers: [$0.token], fnReplace: [], products: [])
      })
    }

    let paths = inputDir.find().extension("swift").type(.file).map { $0 }
    let urls = paths.map { $0.url }
    let processed = try rewrite(urls, prefix: prefix,
                                reports: reports,
                                exclude: exclude,
                                products: productNames,
                                noBaseRewriter: noBase)

    for (idx, syntax) in processed.syntax.enumerated() {
      let path = paths[idx]
      let output = try path.absolutePath(relativeTo: inputDir, in: outputDir)
      var writeTo = try LocalFileOutputByteStream(output, closeOnDeinit: false, buffered: true)
      syntax.write(to: &writeTo)
      try writeTo.close()
    }

    let moduleNames = reports
      .flatMap { $0.products ?? [] }
      .reduce(into: Set(productNames), { $0.insert($1) })

    let headers = inputDir.find().extension("h").type(.file).filter {
      moduleNames.contains($0.basename(dropExtension: true))
    }

    // rename headers, which match any of the module names
    for header in headers {
      let output = header.path(relativeTo: inputDir, in: outputDir)
      try output.rename(to: prefix + output.basename())
    }

    if let identifiersReport = arguments.get(self.report) {
      let reportFile = Path(identifiersReport) ?? Path.cwd/identifiersReport
      let report = SLRIdentifiersReport(prefix: prefix,
                                        identifiers: Array(processed.identifiers),
                                        fnReplace: Array(processed.fnReplace),
                                        products: productNames)
      let encodedData = try JSONEncoder().encode(report)
      try encodedData.write(to: reportFile)

      print("report available at \(reportFile.description)")
    }
  }
}
