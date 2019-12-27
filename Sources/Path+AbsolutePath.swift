//
//  Path+AbsolutePath.swift
//  DePublicize
//
//  Created by Vitaly Aminev on 2019-12-23.
//

import Path
import Basic

extension Path {
  func absolutePath(relativeTo base: Path, in outputDir: Path) throws -> AbsolutePath {
    let absolutePath = outputDir.join(relative(to: base)).url.relativePath
    return try AbsolutePath(validating: absolutePath)
  }
}

extension AbsolutePath {
  var path: Path? {
    return Path(url: self.asURL)
  }
}
