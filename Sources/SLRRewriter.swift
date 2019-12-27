//
//  SLRRewriter.swift
//  DePublicize
//
//  Created by Vitaly Aminev on 2019-12-20.
//

import SwiftSyntax
import Basic
import Foundation

struct SLRIdentifiersReport: Codable {
  let prefix: String;
  let identifiers: [String];
}

class FindPublicAndOpenExports: SyntaxVisitorBase {
  var replace = Set<String>()

  private func isPublic(_ mod: DeclModifierSyntax) -> Bool {
    if mod.name.tokenKind == .publicKeyword {
      return true
    }

    if mod.name.text == "open" {
      return true
    }
    
    return false
  }
  
  override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
    if node.modifiers?.contains(where: isPublic) == true {
      replace.insert(node.identifier.text)
    }

    return .skipChildren
  }
  
  override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
    if node.modifiers?.contains(where: isPublic) == true {
      replace.insert(node.identifier.text)
    }

    return .skipChildren
  }
  
  override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
    if node.modifiers?.contains(where: isPublic) == true {
      replace.insert(node.identifier.text)
    }

    return .skipChildren
  }
  
  override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
    if node.modifiers?.contains(where: isPublic) == true {
      replace.insert(node.identifier.text)
    }

    return .skipChildren
  }
  
  override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
    if node.modifiers?.contains(where: isPublic) == true {
      replace.insert(node.identifier.text)
    }

    return .skipChildren
  }

  override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
    return .skipChildren
  }
  
  override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
    if node.modifiers?.contains(where: isPublic) == true {
      replace.insert(node.letOrVarKeyword.nextToken!.text)
    }

    return .skipChildren
  }
}

class SLRPublicRewriter: SyntaxRewriter {
  let identifiers: Set<String>!
  let prefix: String!
  
  init(ids: Set<String>, prefix: String) {
    self.identifiers = ids
    self.prefix = prefix
  }
  
  override func visit(_ token: TokenSyntax) -> Syntax {
    guard case .identifier(let node) = token.tokenKind else {
      return token
    }
    
    guard identifiers.contains(node) else {
      return token
    }

    return token.withKind(.identifier(prefix + node))
  }
}

func rewrite(_ urls: [URL],
             prefix: String,
             reports: [SLRIdentifiersReport]? = nil) throws -> (syntax: [Syntax], identifiers: Set<String>) {
  var sources = [SourceFileSyntax]()
  var response = [Syntax]()
  var syntaxVisitor = FindPublicAndOpenExports()
  
  for url in urls {
    let sourceFile = try SyntaxParser.parse(url)
    sourceFile.walk(&syntaxVisitor)
    sources.append(sourceFile)
  }
  
  let baseRewriter = SLRPublicRewriter(ids: syntaxVisitor.replace, prefix: prefix)
  let rewriters = reports?.reduce(into: [baseRewriter], { res, rep in
    res.append(SLRPublicRewriter(ids: Set(rep.identifiers), prefix: rep.prefix))
  }) ?? [baseRewriter]

  for idx in urls.indices {
    let sourceFile = sources[idx]
    let syntax = rewriters.reduce(sourceFile) { source, rewriter in
      return rewriter.visit(source)
    }
    response.insert(syntax, at: idx)
  }

  return (response, syntaxVisitor.replace)
}
