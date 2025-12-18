//
//  StringLiteralTokenGenerator.swift
//  PranceCore
//
//  Created by Tristan Burnside on 6/9/19.
//

import Foundation

class StringLiteralTokenGenerator: TokenGenerator {
  
  var isValid: Bool = true
  
  var isComplete: Bool = false
  
  private var isEscaped: Bool = false
  
  private var currentString = ""
  private var parts : [StringPart] = []
  
  private var hasOpeningQuote = false
  private var escapeOpeningCount = 0
  
  func consume(char: Character) {
    guard !isComplete else {
      isValid = false
      return
    }
    if !hasOpeningQuote {
      consumeFirst(char)
    } else if isEscaped {
      if escapeOpeningCount == 0 {
        consumeEscapedOpening(char)
      } else {
        consumeEscaped(char)
      }
    } else {
      consumeBody(char)
    }
  }
  
  func emitToken() throws -> Tokenizable {
    parts.append(.string(currentString))
    return LiteralToken(type: .string(parts))
  }
  
  func reset() {
    hasOpeningQuote = false
    escapeOpeningCount = 0
    currentString = ""
    parts.removeAll()
    isComplete = false
    isValid = true
  }
  
  private func consumeFirst(_ char: Character) {
    guard char == "\"" else {
      isValid = false
      return
    }
    hasOpeningQuote = true
  }
  
  private func consumeBody(_ char: Character) {
    if char == "\"" {
      isComplete = true
    } else if char == "\\" {
      isEscaped = true
      parts.append(.string(currentString))
      currentString = ""
    } else {
      currentString.append(char)
    }
  }
  
  private func consumeEscapedOpening(_ char: Character) {
    guard char == "(" else {
      isValid = false
      return
    }
    escapeOpeningCount = 1
  }
  
  private func consumeEscaped(_ char: Character) {
    if char == "(" {
      escapeOpeningCount += 1
    }
    if char == ")" {
      escapeOpeningCount -= 1
      if escapeOpeningCount == 0 {
        let innerLexer = Lexer()
        do {
          parts.append(.interpolated(try innerLexer.lex(input: currentString + "\n")))
        } catch {
          isValid = false
        }
        isEscaped = false
        currentString = ""
        return
      }
    }
    currentString.append(char)
  }
}
