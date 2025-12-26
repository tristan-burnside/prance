//
//  FunctionCallChecker.swift
//  PranceCore
//
//  Created by Tristan Burnside on 3/4/21.
//

import Foundation

final class FunctionCallChecker: ASTChecker {
  
  let file: File
  
  init(file: File) {
    self.file = file
  }
  
  func check() throws {
    try checkExpr { (expr, _, callables) in
      try validateCallExpr(expr: expr, callables: callables)
    }
  }
  
  private func validateCallExpr(expr: TypedExpr, callables: StackMemory<Prototype>) throws {
    switch expr {
    case .call(let functionCall, _):
      guard let prototype = try? callables.findVariable(name: functionCall.name) else {
        throw ParseError.unknownFunction(functionCall.name)
      }
      try checkCallArgs(call: functionCall, args: prototype.params, callables: callables)
    case .memberDereference(let instance, .function(let call), _):
      let instanceType = (instance.type as? ReferenceStore)?.pointee ?? instance.type
      guard let instanceType = allTypes[instanceType.name] else {
        throw ParseError.typeDoesNotContainMembers(instanceType.name)
      }
      guard let prototype = instanceType.prototypes.first(where: { $0.name == call.name }) else {
        throw ParseError.unknownFunction(call.name)
      }
      try checkCallArgs(call: call, args: prototype.params, callables: callables)
    default:
      break
    }
  }
  
  private func checkCallArgs(call: FunctionCall, args: [VariableDefinition], callables: StackMemory<Prototype>) throws {
    for (passedArg, functionArg) in zip(call.args, args) {
      if passedArg.label != functionArg.name {
        throw ParseError.unexpectedArgumentInCall(got: passedArg.label ?? "", expected: functionArg.name)
      }
      let validTypes = validTypeNames(for: functionArg.type)
      if !validTypes.contains(passedArg.typedExpr.type.resolvedType.name) {
        throw ParseError.wrongType(expectedType: functionArg.type.name, for: functionArg.name, got: passedArg.typedExpr.type.resolvedType.name)
      }
      try validateCallExpr(expr: passedArg.typedExpr, callables: callables)
    }
  }
}
