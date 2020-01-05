//
//  SLRRewriter.swift
//  DePublicize
//
//  Created by Vitaly Aminev on 2019-12-20.
//

import SwiftSyntax
import Basic
import Foundation

struct SLRFuncReport: Codable, Hashable {
  let identifier: String
  let signature: String
}

struct SLRIdentifiersReport: Codable {
  let prefix: String
  let identifiers: [String]
  let fnReplace: [SLRFuncReport]
  let products: [String]?
}

class FindPublicAndOpenExports: SyntaxVisitorBase {
  var replace = Set<String>()

  /// contains list of standard operators, rest will be discovered and added to exclusions
  /// https://github.com/apple/swift/blob/swift-5.1.3-RELEASE/stdlib/public/core/Policy.swift
  var exclude = Set<String>([
    "++", "--", "...", "!",
    "~", "+", "-", "..<",
    "<<", "&<<", ">>", "&>>",
    "*", "&*", "/", "%", "&",
    "&+", "&-", "|", "^",
    "<", "<=", ">", ">=", "==", "!=", "===", "!==", "~=",
    "&&", "||",
    "*=", "&*=", "/=", "%=",
    "+=", "&+=", "-=", "&-=",
    "<<=", "&<<=", ">>=", "&>>=",
    "&=", "^=", "|=", "~>"
  ])

  var fnReplace = Set<SLRFuncReport>()

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
    guard node.modifiers?.contains(where: isPublic) == true else {
      return .skipChildren
    }

    fnReplace.insert(SLRFuncReport(identifier: node.identifier.text, signature: node.signature.description))

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

  override func visit(_ node: OperatorDeclSyntax) -> SyntaxVisitorContinueKind {
    if node.modifiers?.contains(where: isPublic) == true {
      exclude.insert(node.identifier.text)
    }

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
  let fnIdentifiers: Set<SLRFuncReport>!
  let prefix: String!
  let imports: [String]!

  init(ids: Set<String>, prefix: String, fnIdentifiers: Set<SLRFuncReport>, imports: [String]) {
    self.identifiers = ids
    self.prefix = prefix
    self.fnIdentifiers = fnIdentifiers
    self.imports = imports
  }

  override func visit(_ token: TokenSyntax) -> Syntax {
    guard case .identifier(let node) = token.tokenKind else {
      return super.visit(token)
    }

    if identifiers.contains(node) {
      return super.visit(token.withKind(.identifier(prefix + node)))
    }
    
    if imports.contains(node) {
      return super.visit(token.withKind(.identifier(prefix + node)))
    }

    return super.visit(token)
  }

  override func visit(_ node: ObjcNameSyntax) -> Syntax {
    return super.visit(node)
  }

  override func visit(_ node: FunctionDeclSyntax) -> DeclSyntax {
    guard fnIdentifiers.contains(where: { $0.identifier == node.identifier.text && $0.signature == node.signature.description }) else {
      return super.visit(node)
    }

    return super.visit(node.withIdentifier(node.identifier.withKind(.identifier(prefix + node.identifier.text))))
  }

  override func visit(_ node: ImportDeclSyntax) -> DeclSyntax {
    guard node.path.count > 0, let name = node.path.firstToken?.text, imports.contains(name) else {
      return super.visit(node)
    }
    
    guard let firstPart = node.path.children.first(where: { _ in true }) as? AccessPathComponentSyntax else {
      return super.visit(node)
    }
  
    return super.visit(node.withPath(node.path.replacing(childAt: 0, with: firstPart.withName(firstPart.name.withKind(.identifier(prefix + name))))))
  }
}

func rewrite(
  _ urls: [URL],
  prefix: String,
  reports: [SLRIdentifiersReport]? = nil,
  exclude: [String]? = nil,
  products: [String]? = nil
) throws -> (syntax: [Syntax], identifiers: Set<String>, fnReplace: Set<SLRFuncReport>) {
    var sources = [SourceFileSyntax]()
    var response = [Syntax]()
    var syntaxVisitor = FindPublicAndOpenExports()
 
    if let exclude = exclude {
      syntaxVisitor.exclude.formUnion(exclude)
    }

    for url in urls {
      let sourceFile = try SyntaxParser.parse(url)
      sourceFile.walk(&syntaxVisitor)
      sources.append(sourceFile)
    }

    // removes exclusions
    syntaxVisitor.fnReplace = syntaxVisitor.fnReplace.filter {
      !syntaxVisitor.exclude.contains($0.identifier)
    }

    syntaxVisitor.replace = syntaxVisitor.replace.filter {
      !syntaxVisitor.exclude.contains($0)
    }

    let baseRewriter = SLRPublicRewriter(ids: syntaxVisitor.replace,
                                         prefix: prefix,
                                         fnIdentifiers: syntaxVisitor.fnReplace,
                                         imports: products ?? [])

    let rewriters = reports?.reduce(into: [baseRewriter], { res, rep in
      res.append(SLRPublicRewriter(ids: Set(rep.identifiers),
                                   prefix: rep.prefix,
                                   fnIdentifiers: Set(rep.fnReplace),
                                   imports: rep.products ?? []))
    }) ?? [baseRewriter]

    for idx in urls.indices {
      let sourceFile = sources[idx]
      let syntax = rewriters.reduce(sourceFile) { source, rewriter in
        return rewriter.visit(source)
      }
      response.insert(syntax, at: idx)
    }

    return (response, syntaxVisitor.replace, syntaxVisitor.fnReplace)
}
