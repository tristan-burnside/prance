import SwiftyLLVM

protocol StoredType: AnyObject {
  var IRType: IRType? { get set }
  var IRRef: IRType? { get set }
  var name: String { get }
  var stringFormat: String { get }
  var module: Module? { get set }
  
  func loadedType(types: [String: any CallableType], in module: inout Module) throws -> IRType?
  func loadedRef(types: [String: any CallableType], in module: inout Module) throws -> IRType?
  
  var resolvedType: StoredType { get }
}

final class CustomStore: StoredType {
  // Type is currently unknown
  var IRType: IRType? = nil
  var IRRef: IRType? = nil
  let name: String
  
  var stringFormat: String {
    "%s"
  }
  
  init(name: String) {
    self.name = name
  }
  
  var module: Module?
}

final class ReferenceStore: StoredType {
  var IRType: IRType? {
    get {
      guard var module else { fatalError() }
      return PointerType(in: &module)
    }
    set {
      // Nothing to see here
    }
  }
  var IRRef: IRType? {
    get {
      guard var module else { fatalError() }
      return PointerType(in: &module)
    }
    set {
      // Nothing to see here
    }
  }
  let name: String = "Pointer"
  var module: Module?
  
  var stringFormat: String {
    pointee.stringFormat
  }
  
  let pointee: StoredType
  
  init(pointee: StoredType) {
    self.pointee = pointee
  }
  
  func loadedType(types: [String : any CallableType], in module: inout Module) throws -> (any IRType)? {
    try pointee.findType(types: types, in: module)
  }
  
  func loadedRef(types: [String : any CallableType], in module: inout Module) throws -> (any IRType)? {
    try pointee.findRef(types: types, in: module)
  }
  
  var resolvedType: any StoredType {
    return pointee
  }
}
