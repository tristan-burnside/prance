//
//  VariableAssignmentTypeChecker.swift
//  PranceCore
//
//  Created by Tristan Burnside on 3/7/21.
//

import Foundation

final class VariableAssignmentTypeChecker: ASTChecker {
  let file: File
  
  init(file: File) {
    self.file = file
  }
  
  func check() throws {
    try checkExpr { (expr, parameterValues, _) in
      switch expr {
      case .variableAssignment(let variableExpr, let storedExpr, _):
        let variableType = variableExpr.type.resolvedType
        let storedType = storedExpr.type.resolvedType
        let assignableTypeNames = validTypeNames(for: variableType)
        if !assignableTypeNames.contains(storedType.name) {
          throw ParseError.unableToAssign(type: storedType.name, to: storedType.name)
        }
      default:
        break
      }
    }
  }
}
