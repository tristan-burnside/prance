import SwiftyLLVM

final class DoubleStore: StoredType {
  
  var IRType: IRType? {
    get {
      guard var module else {
        fatalError("Doubles must be in a module to be emitted")
      }
      return FloatingPointType.double(in: &module)
    }
    set {
      // Not implemented because this type is already known
    }
  }
  var IRRef: IRType? {
    get {
      guard var module else {
        fatalError("Doubles must be in a module to be emitted")
      }
      return FloatingPointType.double(in: &module)
    }
    set {
      // Not implemented because this type is already known
    }
  }
  let name = "Double"
  
  var stringFormat: String {
    "%lf"
  }
  
  var module: Module?
}

final class IntStore: StoredType {
  let name = "Int"
  var IRType: IRType? {
    get {
      guard var module else {
        fatalError("Ints must be in a module to be emitted")
      }
      return IntegerType(MemoryLayout<Int>.size * 8, in: &module)
    }
    set {
      // Not implemented because this type is already known
    }
  }
  
  var IRRef: IRType? {
    get {
      guard var module else {
        fatalError("Ints must be in a module to be emitted")
      }
      return IntegerType(MemoryLayout<Int>.size * 8, in: &module)
    }
    set {
      // Not implemented because this type is already known
    }
  }
  
  var stringFormat: String {
    "%d"
  }

  var module: Module?
}

final class FloatStore: StoredType {
  let name = "Float"
  var IRType: IRType? {
    get {
      guard var module else {
        fatalError("Floats must be in a module to be emitted")
      }
      return FloatingPointType.float(in: &module)
    }
    set {
      // Not implemented because this type is already known
    }
  }
  
  var IRRef: IRType? {
    get {
      guard var module else {
        fatalError("Floats must be in a module to be emitted")
      }
      return FloatingPointType.float(in: &module)
    }
    set {
      // Not implemented because this type is already known
    }
  }
  
  var stringFormat: String {
    "%f"
  }
  
  var module: Module?
}

final class StringStore: StoredType {
  let name = "String"
  var IRType: IRType? {
    get {
      guard var module else {
        fatalError("Strings must be in a module to be emitted")
      }
      return PointerType(pointee: module.i8, in: &module)
    }
    set {
      // Not implemented because this type is already known
    }
  }

  var IRRef: IRType? {
    get {
      guard var module else {
        fatalError("Strings must be in a module to be emitted")
      }
      return PointerType(pointee: module.i8, in: &module)
    }
    set {
      // Not implemented because this type is already known
    }
  }
  
  var stringFormat: String {
    "%s"
  }
  
  var module: Module?
}

final class VoidStore: StoredType {
  let name = ""
  var IRType: IRType? {
    get {
      guard var module else {
        fatalError("Voids must be in a module to be emitted")
      }
      return VoidType(in: &module)
    }
    set {
      // Not implemented because this type is already known
    }
  }
  
  var IRRef: IRType? {
    get {
      guard var module else {
        fatalError("Voids must be in a module to be emitted")
      }
      return VoidType(in: &module)
    }
    set {
      // Not implemented because this type is already known
    }
  }
  
  var stringFormat: String {
    fatalError("Voids cannot be part of a format string")
  }
  
  var module: Module?
  
  init() {}
}
