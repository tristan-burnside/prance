import SwiftyLLVM

let kInternalPropertiesCount = 2

enum IRError: Error, CustomStringConvertible {
  case unknownFunction(String)
  case unknownVariable(String)
  case wrongNumberOfArgs(String, expected: Int, got: Int)
  case incorrectFunctionLabel(String, expected: String, got: String)
  case nonTruthyType(IRType)
  case unprintableType(IRType)
  case unableToCompare(IRType, IRType)
  case expectedParameterDefinition(String)
  case unknownMember(String)
  case unknownMemberFunction(String, in: String)
  case unknownType(String)
  case incorrectlyParsedLiteral
  case missingFunction(String, String)
  case returnOutsideFunction
  
  var description: String {
    switch self {
    case .unknownFunction(let name):
      return "unknown function '\(name)'"
    case .unknownVariable(let name):
      return "unknown variable '\(name)'"
    case .wrongNumberOfArgs(let name, let expected, let got):
      return "call to function '\(name)' with \(got) arguments (expected \(expected))"
    case .incorrectFunctionLabel(let name, let expected, let got):
      return "call to function '\(name)' expected parameter \(expected) received \(got)"
    case .nonTruthyType(let type):
      return "logical operation found non-truthy type: \(type)"
    case .unprintableType(let type):
      return "unable to print result of type \(type)"
    case .unableToCompare(let type1, let type2):
      return "unable to compare \(type1) with \(type2)"
    case .expectedParameterDefinition(let name):
      return "expected parameter definition in declaration of function \(name)"
    case .unknownMember(let name):
      return "No member: \(name) in type"
    case .unknownMemberFunction(let name, let type):
      return "No function: \(name) in type \(type)"
    case .unknownType(let name):
      return "No type defined called \(name)"
    case .incorrectlyParsedLiteral:
      return "String literal was not parsed before generating LLVM IR"
    case .missingFunction(let typeName, let name):
      return "Type: \(typeName) is missing protocol function \(name)"
    case .returnOutsideFunction:
      return "Return statement executed outside of function body"
    }
  }
}

//func ==(lhs: IRType, rhs: IRType) -> Bool {
//    return lhs.llvm == rhs.llvm
//}

class IRGenerator {
  var module: Module
  var currentInsertion: InsertionPoint!
  var currentFunction: Function!
  let file: File
  let protocolType: StructType
  
  private var parameterValues: StackMemory<IRValue>
  private var callables: StackMemory<Prototype>
  private var typesByIR: [(IRType, TypeDefinition)]
  private var typesByName: [String: CallableType]
  private var typesByID: [Int32: TypeDefinition]
  private var nextTypeID: Int32 = 0
  private var currentReturnBlock: BasicBlock?
  
  init(moduleName: String = "main", file: File) {
    self.module = Module(moduleName)
    self.file = file
    parameterValues = StackMemory()
    typesByName = [:]
    typesByIR = []
    typesByID = [:]
    protocolType = IRGenerator.defineProtocolStruct(module: &module)
    callables = StackMemory()
    callables.startFrame()
    for (name, proto) in file.prototypeMap {
      callables.addVariable(name: name, value: proto)
    }
  }
  
  func emit() throws {
    emitPrintf()
    emitScanf()
    for extern in file.externs {
      try emitPrototype(extern)
    }
    try emitCopyStr()
    try emitScanLine()
    for type in file.customTypes {
      defineType(type)
    }
    for proto in file.protocols {
      defineProtocol(proto)
    }
    for type in file.customTypes {
      try populateType(type)
    }
    for proto in file.protocols {
      try emitProtocolFunctions(proto: proto)
    }
    for definition in file.functions {
      try emitFunction(definition)
    }
    try emitMain()
  }
  
  func emitPrintf() {
    guard module.function(named: "printf") == nil else { return }
    let printfType = FunctionType(from: [PointerType(in: &module)], to: IntegerType(32, in: &module), isVarArg: true, in: &module)
    let _ = module.declareFunction("printf", printfType)
    
    let sPrintfType = FunctionType(from: [PointerType(in: &module), PointerType(in: &module)], to: IntegerType(32, in: &module), isVarArg: true, in: &module)
    let _ = module.declareFunction("sprintf", sPrintfType)
  }
  
  func emitScanf() {
    guard module.function(named: "scanf") == nil else { return }
    let printfType = FunctionType(from: [PointerType(in: &module)], to: IntegerType(32, in: &module), isVarArg: true, in: &module)
    let _ = module.declareFunction("scanf", printfType)
  }
  
  func emitScanLine() throws {
    guard let prototype = file.prototypeMap["scanLine"] else {
      return
    }
    
    guard let copyFunc = module.function(named: ".copyStr") else {
      throw IRError.unknownFunction(".copyStr")
    }
    
    let function = try emitPrototype(prototype)
    
    parameterValues.startFrame()
    
    for (idx, arg) in prototype.params.enumerated() {
      let param = function.parameters[idx]
      parameterValues.addStatic(name: arg.name, value: param)
    }
    
    let entryBlock = module.appendBlock(named: "entry", to: function)
    let blockInsertionPoint = module.endOf(entryBlock)
    
    //Body
    
    // create temp
    let section = module.insertAlloca(ArrayType(20, IntegerType(8, in: &module), in: &module), at: blockInsertionPoint)
    let format = module.insertGlobalStringPointer("%19s%n", name: "scanFormat", at: blockInsertionPoint)
    let scannedChars = module.insertAlloca(module.i32, at: blockInsertionPoint)
    let resultChars = module.insertAlloca(module.i32, at: blockInsertionPoint)
    let resultSize = module.insertAlloca(module.i32, at: blockInsertionPoint)
    let resultPtr = module.insertAlloca(PointerType(pointee: module.i8, in: &module), at: blockInsertionPoint)
    let initialResult = module.insertMalloc(module.i8, count: module.i32.constant(20), at: blockInsertionPoint)
    module.insertStore(module.i32.zero, to: resultChars, at: blockInsertionPoint)
    module.insertStore(module.i32.constant(20), to: resultSize, at: blockInsertionPoint)
    module.insertStore(initialResult, to: resultPtr, at: blockInsertionPoint)
    guard let scanf = file.prototypeMap["scanf"] else {
      throw IRError.unknownFunction("scanf")
    }
    let scanfFunction = try emitPrototype(scanf)
    
    // while more chars
    let scanBlock = module.appendBlock(named: "scan", to: function)
    let addSpaceBlock = module.appendBlock(named: "addSpace", to: function)
    let saveBlock = module.appendBlock(named: "save", to: function)
    let endScanBlock = module.appendBlock(named: "end_scan", to: function)
    let returnBlock = module.appendBlock(named: "return", to: function)
    module.insertBr(to: scanBlock, at: blockInsertionPoint)
    let scanInsertion = module.endOf(scanBlock)
    // scanf
    let args: [IRValue] = [format, section, scannedChars]
    let _ = module.insertCall(scanfFunction, on: args, at: scanInsertion)
    let scannedCharsValue = module.insertLoad(module.i32, from: scannedChars, at: scanInsertion)
    // save partial
    let oldResultCharsVal = module.insertLoad(module.i32, from: resultChars, at: scanInsertion)
    let newResultCharsVal = module.insertAdd(oldResultCharsVal, scannedCharsValue, at: scanInsertion)
    module.insertStore(newResultCharsVal, to: resultChars, at: scanInsertion)
    let resultSizeVal = module.insertLoad(module.i32, from: resultSize, at: scanInsertion)
    let needSpace = module.insertIntegerComparison(.sgt, newResultCharsVal, resultSizeVal, at: scanInsertion)
    let currentCharPtr = module.insertAlloca(module.i32, at: scanInsertion)
    module.insertStore(module.i32.zero, to: currentCharPtr, at: scanInsertion)
    module.insertCondBr(if: needSpace, then: addSpaceBlock, else: saveBlock, at: scanInsertion)
    
    let addSpaceInsertion = module.endOf(addSpaceBlock)
    let oldResult = module.insertLoad(PointerType(pointee: module.i8, in: &module), from: resultPtr, at: addSpaceInsertion)
    let oldResultSize = module.insertLoad(module.i32, from: resultSize, at: addSpaceInsertion)
    let newResultSize = module.insertMul(overflow: .nuw, oldResultSize, module.i32.constant(2), at: addSpaceInsertion)
    let newResult = module.insertMalloc(module.i8, count: newResultSize, at: addSpaceInsertion)
    let _ = module.insertCall(copyFunc, on: [oldResult, newResult, oldResultSize], at: addSpaceInsertion)
    module.insertStore(newResultSize, to: resultSize, at: addSpaceInsertion)
    module.insertStore(newResult, to: resultPtr, at: addSpaceInsertion)
    module.insertFree(oldResult, at: addSpaceInsertion)
    module.insertBr(to: saveBlock, at: addSpaceInsertion)
    
    let saveInsertion = module.endOf(saveBlock)
    let nextCharPtr = module.insertLoad(PointerType(pointee: module.i8, in: &module), from: resultPtr, at: saveInsertion)
    let nextChar = module.insertGetElementPointer(of: nextCharPtr, typed: module.i8, indices: [oldResultCharsVal], at: saveInsertion)
    let scannedCharPtr = module.insertGetElementPointer(of: section, typed: module.i8, indices: [module.i32.zero], at: saveInsertion)
    let _ = module.insertCall(copyFunc, on: [scannedCharPtr, nextChar, scannedCharsValue], at: saveInsertion)
    module.insertBr(to: endScanBlock, at: saveInsertion)
    
    // end while
    let endInsertion = module.endOf(endScanBlock)
    let cont = module.insertIntegerComparison(.eq, scannedCharsValue, module.i32.constant(19), at: endInsertion)
    module.insertCondBr(if: cont, then: scanBlock, else: returnBlock, at: endInsertion)
    // allocate mem for output
    let returnInsertion = module.endOf(returnBlock)
    // return
    let result = module.insertLoad(PointerType(pointee: module.i8, in: &module), from: resultPtr, at: returnInsertion)
    let resultCharsCount = module.insertAdd(newResultCharsVal, module.i32.constant(1), at: returnInsertion)
    let retBuffer = module.insertMalloc(module.i8, count: resultCharsCount, at: returnInsertion)

    let _ = module.insertCall(copyFunc, on: [result, retBuffer, resultCharsCount], at: returnInsertion)
    module.insertFree(result, at: returnInsertion)
    module.insertReturn(retBuffer, at: returnInsertion)
    parameterValues.endFrame()
  }
  
  func emitCopyStr() throws {
    let function = module.declareFunction(".copyStr", FunctionType(from: [PointerType(pointee: module.i8, in: &module),
                                                                          PointerType(pointee: module.i8, in: &module),
                                                                          module.i32], to: module.void, isVarArg: false, in: &module))
    let entry = module.appendBlock(named: "entry", to: function)
    let copy = module.appendBlock(named: "copy", to: function)
    let returnBlock = module.appendBlock(named: "return", to: function)
    currentInsertion = module.endOf(entry)
    let currentChar = module.insertAlloca(module.i32, at: currentInsertion)
    module.insertStore(module.i32.zero, to: currentChar, at: currentInsertion)
    guard function.parameters.count == 3  else {
      throw IRError.wrongNumberOfArgs("copyStr", expected: 3, got: 2)
    }
    let fromStr = function.parameters[0]
    let toStr = function.parameters[1]
    let charsToCopy = function.parameters[2]
    module.insertBr(to: copy, at: currentInsertion)
    currentInsertion = module.endOf(copy)
    let currentCharValue = module.insertLoad(module.i32, from: currentChar, at: currentInsertion)
    let from = module.insertGetElementPointer(of: fromStr, typed: module.i8, indices: [currentCharValue], at: currentInsertion)
    let to = module.insertGetElementPointer(of: toStr, typed: module.i8, indices: [currentCharValue], at: currentInsertion)
    let fromValue = module.insertLoad(module.i8, from: from, at: currentInsertion)
    module.insertStore(fromValue, to: to, at: currentInsertion)
    let newChar = module.insertAdd(currentCharValue, module.i32.constant(1), at: currentInsertion)
    module.insertStore(newChar, to: currentChar, at: currentInsertion)
    let cont = module.insertIntegerComparison(.eq, charsToCopy, newChar, at: currentInsertion)
    module.insertCondBr(if: cont, then: returnBlock, else: copy, at: currentInsertion)
    currentInsertion = module.endOf(returnBlock)
    module.insertReturn(at: currentInsertion)
  }
  
  func debugPrint(value: IRValue) {
    let printValue: IRValue
    if let type = value.type as? PointerType, let pointee = type.pointee {
      printValue = module.insertLoad(pointee, from: value, at: currentInsertion)
    } else {
      printValue = value
    }
    guard let printf = module.function(named: "printf") else { return }
    let format = module.insertGlobalStringPointer("%d\n", name: "debugFormat", at: currentInsertion)
    _ = module.insertCall(printf, on: [format, printValue], at: currentInsertion)
  }
  
  func defineType(_ type: TypeDefinition) {
    let newType = StructType(named: type.name, [], in: &module)
    type.IRType = newType
    type.IRRef = PointerType(pointee: newType, in: &module)
    typesByIR.append((newType, type))
    typesByName[type.name] = type
  }
  
  func defineProtocol(_ proto: ProtocolDefinition) {
    proto.IRType = protocolType
    proto.IRRef = PointerType(in: &module)
    
    typesByName[proto.name] = proto
  }
  
  static func defineProtocolStruct(module: inout Module) -> StructType {
    let properties = [IntegerType(32, in: &module), IntegerType(32, in: &module)]
    let llvmProtocol = StructType(named: "proto", properties, in: &module)//builder.createStruct(name: "proto", types: properties)
    return llvmProtocol
  }
  
  func populateType(_ type: TypeDefinition) throws {
    guard let llvmType = type.IRType else {
      throw IRError.unknownType(type.name)
    }
    let properties = try type.properties.map{ try $0.1.findRef(types: typesByName, in: module) }
    let internalProperties = [module.i32, module.i32]
    llvmType.setFields(internalProperties + properties)
    try emitInitializer(type.initMethod, for: type)
    for proto in type.prototypes {
      let conformance = type.protocolConformanceStubs.first(where: {
        $0.1.name == proto.name
      })
      if conformance?.2 == false {
        try emitMemberStub(prototype: conformance?.1 ?? proto, of: type, conforms: conformance?.0 ?? "")
      } else {
        try emitMember(function: type.functions[proto.name]!, of: type, conforming: conformance?.0)
      }
    }
  }
  
  func emitMain() throws {
    parameterValues.startFrame()
    defer {
      parameterValues.endFrame()
    }
    let mainType = FunctionType(from: [], to: module.void, isVarArg: false, in: &module)
    let function = module.declareFunction("main", mainType)
    let entry = module.appendBlock(named: "entry", to: function)
    currentInsertion = module.endOf(entry)
    currentFunction = function
    for expr in file.typedExpressions {
      let _ = try emitExpr(expr)
    }
    
    module.insertReturn(at: currentInsertion)
  }
  
  @discardableResult
  func emitMember(prototype: Prototype, of type: CallableType) throws -> Function {
    let llvmPrototype = try internalPrototype(for: prototype, of: type.name)
    return try emitPrototype(llvmPrototype)
  }
  
  @discardableResult
  func emitMemberStub(prototype: Prototype, of type: CallableType, conforms: String) throws -> Function {
    guard let matchingType = typesByName[conforms] else {
      throw IRError.unknownMemberFunction(prototype.name, in: conforms)
    }
    var defaultPrototype = prototype
    defaultPrototype.name += ".default"
    let prototypeFunction = try emitMember(prototype: defaultPrototype, of: matchingType)
    
    let function = try emitMember(prototype: prototype, of: type)
    let entry = module.appendBlock(named: "entry", to: function)
    currentInsertion = module.endOf(entry)
    let protocolSelf = module.insertCast(.bitCast, function.parameters[0], to: PointerType(pointee: protocolType, in: &module), at: currentInsertion)
    let protocolParameters = [protocolSelf] + (Array(function.parameters.dropFirst()) as! [IRValue])
    let ret = module.insertCall(prototypeFunction, on: protocolParameters, at: currentInsertion)
    module.insertReturn(ret, at: currentInsertion)
    return function
  }
  
  
  @discardableResult
  func emitMember(function: FunctionDefinition, of type: CallableType, conforming: String?) throws -> Function {
    callables.startFrame()
    
    let llvmPrototype = try internalPrototype(for: function.prototype, of: type.name)
    let llvmFunction = FunctionDefinition(prototype: llvmPrototype, expr: function.expr)
    llvmFunction.typedExpr = function.typedExpr
    if let conforming {
      var prototype = function.prototype
      prototype.name += ".default"
      callables.addVariable(name: "default", value: try internalPrototype(for: prototype, of: conforming))
    }
    let function = try emitFunction(llvmFunction)
    callables.endFrame()
    return function
  }
  
  func internalPrototype(for prototype: Prototype, of type: String) throws -> Prototype {
    // Add self arg reference
    let internalName = type + "." + prototype.name
    let selfType = CustomStore(name: type)
    let internalParams = [VariableDefinition(name: "self", type: selfType)] + prototype.params
    return Prototype(name: internalName, params: internalParams, returnType: prototype.returnType)
  }
  
  func emitProtocolFunctions(proto: ProtocolDefinition) throws {
    let conformingTypes = typesByIR.map { $0.1 }.filter { $0.protocols.contains(proto.name) }
    
    for prototype in proto.prototypes {
      let internalDefinition = try internalPrototype(for: prototype, of: proto.name)
      let defaultImpl = proto.defaults[prototype.name]
      try emitProtocolMember(name: prototype.name, prototype: internalDefinition, conformingTypes: conformingTypes, defaultImpl: defaultImpl)
    }
  }
  
  func emitProtocolMember(name: String, prototype: Prototype, conformingTypes: [TypeDefinition], defaultImpl: FunctionDefinition?) throws {
    let function = try emitPrototype(prototype)
    parameterValues.startFrame()
    
    for (idx, arg) in prototype.params.enumerated() {
      let param = function.parameters[idx]
      parameterValues.addStatic(name: arg.name, value: param)
    }
    
    let entryBlock = module.appendBlock(named: "entry", to: function)
    let returnBlock = module.appendBlock(named: "return", to: function)
    let defaultBlock = module.appendBlock(named: "default", to: function)
    currentReturnBlock = returnBlock
    
    currentInsertion = module.endOf(entryBlock)
    if prototype.returnType.name != VoidStore().name {
      let _ = try emitExpr(.variableDefinition(VariableDefinition(name: ".return", type: ReferenceStore(pointee: prototype.returnType)), VoidStore()))
    }
    
    let selfIR = try parameterValues.findVariable(name: "self")
    let typeIDRef = module.insertGetStructElementPointer(of: selfIR, typed: protocolType, index: 0, at: currentInsertion)
    let typeID = module.insertLoad(module.i32, from: typeIDRef, at: currentInsertion)
    
    var cases = [(IRValue, BasicBlock)]()
    
    for type in conformingTypes {
      if let typedFunction = type.functions[name] {
        let typeBlock = module.appendBlock(named: type.name, to: function)
        currentInsertion = module.endOf(typeBlock)
        // bitcast to type
        guard let typeIRRef = type.IRRef else { throw IRError.unknownType(type.name) }
        let typedSelf = module.insertCast(.bitCast, selfIR, to: typeIRRef, at: currentInsertion)
        // call type version of function
        let typedFunctionIR = try emitMember(prototype: typedFunction.prototype, of: type)
        var typedParameters = Array(function.parameters) as! [any IRValue]
        typedParameters[0] = typedSelf
        let call = module.insertCall(typedFunctionIR, on: typedParameters, at: currentInsertion)
        
        if prototype.returnType.name != VoidStore().name {
          module.insertStore(call, to: try parameterValues.findVariable(name: ".return"), at: currentInsertion)
        }
        let _ = try emitExpr(.return(nil, prototype.returnType))
        
        cases.append((module.i32.constant(type.id!), typeBlock))
      }
    }
    
    currentInsertion = module.endOf(entryBlock)
    module.insertSwitch(on: typeID, cases: cases, default: defaultBlock, at: currentInsertion)

    if let defaultImpl {
      defaultImpl.prototype = prototype
      try emitFunction(defaultImpl)
    }
    
    let argTypes = try prototype.params.map{ $0.type }.map{ try $0.findRef(types: typesByName, in: module) }
    let defaultType = FunctionType(from: argTypes, to: prototype.returnType.IRType, isVarArg: false, in: &module)
    let defaultFunction = module.declareFunction(function.name + ".default", defaultType)
    
    currentInsertion = module.endOf(defaultBlock)
    let defaultReturn = module.insertCall(defaultFunction, on: Array(function.parameters), at: currentInsertion)
    if prototype.returnType.name != VoidStore().name {
      module.insertStore(defaultReturn, to: try parameterValues.findVariable(name: ".return"), at: currentInsertion)
    }
    module.insertBr(to: returnBlock, at: currentInsertion)
    
    currentInsertion = module.endOf(returnBlock)
    if prototype.returnType.name == VoidStore().name {
      module.insertReturn(at: currentInsertion)
    } else {
      let returnVar = try parameterValues.findVariable(name: ".return")
      let returnVal = try value(from: returnVar, with: ReferenceStore(pointee: prototype.returnType)).0
      module.insertReturn(returnVal, at: currentInsertion)
    }
    
    parameterValues.endFrame()
  }
  
  @discardableResult // declare double @foo(double %n, double %m)
  func emitPrototype(_ prototype: Prototype) throws -> Function {
    if let function = module.function(named: prototype.name) {
      return function
    }
    let argTypes = try prototype.params.map{ $0.type }.map{ try $0.findRef(types: typesByName, in: module) }
    
    let funcType = try FunctionType(from: argTypes, to: prototype.returnType.findRef(types: typesByName, in: module), isVarArg: false, in: &module)
    let function = module.declareFunction(prototype.name, funcType)
    
    for (var param, name) in zip(function.parameters, prototype.params.map{ $0.name }) {
      param.name = name
    }
    
    return function
  }
  
  @discardableResult
  func emitFunction(_ definition: FunctionDefinition) throws -> Function {
    var prototype = definition.prototype
    if definition.isDefault {
      prototype.name += ".default"
    }
    let function = try emitPrototype(prototype)
    currentFunction = function
    parameterValues.startFrame()
    
    for (idx, arg) in definition.prototype.params.enumerated() {
      let param = function.parameters[idx]
      parameterValues.addStatic(name: arg.name, value: param)
    }
    
    let entryBlock = module.appendBlock(named: "entry", to: function)
    let returnBlock = module.appendBlock(named: "return", to: function)
    currentReturnBlock = returnBlock
    
    currentInsertion = module.endOf(entryBlock)
    
    if definition.prototype.returnType.name != VoidStore().name {
      let _ = try emitExpr(.variableDefinition(VariableDefinition(name: ".return", type: ReferenceStore(pointee: definition.prototype.returnType)), VoidStore()))
    }
    
    try definition.typedExpr.forEach {
      let _ = try emitExpr($0)
    }
    
    if definition.prototype.returnType is VoidStore,
      !(definition.expr.last is Returnable) {
      let _ = try emitExpr(.return(nil, VoidStore()))
    }
    
    currentInsertion = module.endOf(returnBlock)
    if definition.prototype.returnType.name == VoidStore().name {
      module.insertReturn(at: currentInsertion)
    } else {
      let returnVar = try parameterValues.findVariable(name: ".return")
      let returnVal = try value(from: returnVar, with: ReferenceStore(pointee: definition.prototype.returnType)).0
      module.insertReturn(returnVal, at: currentInsertion)
    }
    
    parameterValues.endFrame()
    currentFunction = nil
    return function
  }
  
  @discardableResult
  func emitInitializer(_ definition: FunctionDefinition, for type: TypeDefinition) throws -> Function {
    guard let llvmType = type.IRType else {
        throw IRError.unknownType(type.name)
    }
    let function = try emitPrototype(definition.prototype)
    currentFunction = function
    parameterValues.startFrame()
    
    for (idx, arg) in definition.prototype.params.enumerated() {
      let param = function.parameters[idx]
      parameterValues.addStatic(name: arg.name, value: param)
    }
    
    let entryBlock = module.appendBlock(named: "alloc", to: function)
    
    let returnBlock = module.appendBlock(named: "return", to: function)
    currentReturnBlock = returnBlock
    
    currentInsertion = module.endOf(entryBlock)
    let _ = try emitExpr(.variableDefinition(VariableDefinition(name: ".return", type: ReferenceStore(pointee: definition.prototype.returnType)), VoidStore()))
    
    let selfPtr = module.insertMalloc(llvmType, at: currentInsertion)
    parameterValues.addStatic(name: "self", value: selfPtr)
    let typeIDPtr = module.insertGetStructElementPointer(of: selfPtr, typed: llvmType, index: 0, at: currentInsertion)
    module.insertStore(module.i32.constant(register(type: type)), to: typeIDPtr, at: currentInsertion)
    let arcPtr = module.insertGetStructElementPointer(of: selfPtr, typed: llvmType, index: 1, at: currentInsertion)
    module.insertStore(module.i32.zero, to: arcPtr, at: currentInsertion)
    
    try definition.typedExpr.forEach { let _ = try emitExpr($0) }
    
    currentInsertion = module.endOf(returnBlock)
    let returnVar = try parameterValues.findVariable(name: ".return")
    let returnVal = try value(from: returnVar, with: ReferenceStore(pointee: definition.prototype.returnType)).0
    module.insertReturn(returnVal, at: currentInsertion)
    
    parameterValues.endFrame()
    currentFunction = nil
    return function
  }
  
  func register(type: TypeDefinition) -> Int32 {
    typesByID[nextTypeID] = type
    type.id = nextTypeID
    defer {
      nextTypeID += 1
    }
    return nextTypeID
  }
  
  func emitExpr(_ expr: TypedExpr) throws -> (IRValue, StoredType) {
    switch expr {
    case .variableDefinition(let definition, let type):
      let newVar = module.insertAlloca(try definition.type.findRef(types: typesByName, in: module), at: currentInsertion)
      parameterValues.addVariable(name: definition.name, value: newVar)
      return (Undefined(of: module.void), type)
    case .variable(let name, let type):
      let value = try parameterValues.findVariable(name: name)
      return (value, type)
    case .memberDereference(let instance, .property(let member), let type):
        let (instanceIR, instanceType) = try emitExpr(instance)
      guard let matchingType = typesByName[instanceType.resolvedType.name] else {
        throw IRError.unknownType(instanceType.resolvedType.name)
        }
        let members = matchingType.properties.enumerated().filter{ $1.0 == member }
        guard let (elementIndex, _) = members.first else {
            throw IRError.unknownMember(member)
        }
      let resolvedInstanceIR = try value(from: instanceIR, with: instanceType).0
      let memberRef = module.insertGetStructElementPointer(of: resolvedInstanceIR, typed: StructType(try instanceType.resolvedType.findType(types: typesByName, in: module))!, index: elementIndex + kInternalPropertiesCount, at: currentInsertion)
      return (memberRef, type)
    case .memberDereference(let instance, .function(let functionCall), let type):
      let (instanceIR, instanceType) = try emitExpr(instance)
      
      guard let matchingType = typesByName[((instanceType as? ReferenceStore)?.pointee ?? instanceType).name] else {
        throw IRError.unknownMemberFunction(functionCall.name, in: instanceType.name)
      }
      let functions = matchingType.prototypes.filter{ $0.name == functionCall.name }
      guard let function = functions.first else {
        throw IRError.unknownMemberFunction(functionCall.name, in: matchingType.name)
      }
      guard function.params.count == functionCall.args.count else {
        throw IRError.wrongNumberOfArgs(functionCall.name,
                                        expected: function.params.count,
                                        got: functionCall.args.count)
      }
      try zip(function.params, functionCall.args).forEach { (protoArg, callArg) in
        if protoArg.name != callArg.label {
          throw IRError.incorrectFunctionLabel(function.name,
                                               expected: protoArg.name,
                                               got: callArg.label ?? "")
        }
      }
      let llvmFunction = try emitMember(prototype: function, of: matchingType)
      let callArgs = try functionCall.args.map{
        $0.typedExpr
      }.map(emitExprAndLoad)
        .map {
          $0.0
        }
      let callReturn = module.insertCall(llvmFunction, on: [try value(from: instanceIR, with: instanceType).0] + callArgs, at: currentInsertion)
      return (callReturn, type)
    case .variableAssignment(let variable, let expr, let type):
      let (variablePointer, ptrType) = try emitExpr(variable)
      let (value, valueType) = try emitExpr(expr)
      var castValue = value
      let resolvedType = (ptrType as? ReferenceStore)?.pointee ?? type
      if resolvedType.name != valueType.name {
        castValue = module.insertCast(.bitCast, value, to: try resolvedType.findRef(types: typesByName, in: module), at: currentInsertion)
      }
      module.insertStore(castValue, to: variablePointer, at: currentInsertion)

      return (Undefined(of: module.void), type)

    case .literal(.double(let value), let type):
      return (module.double.constant(value), type)
    case .literal(.float(let value), let type):
      return (module.float.constant(Double(value)), type)
    case .literal(.integer(let value), let type):
      // TODO: Define as natural width int
      return (module.i64.constant(value), type)
    case .literal(.string(let parts), let type):
      if case let .string(string) = parts.first {
        let globalString = module.insertGlobalStringPointer(string, name: "", at: currentInsertion)
        return (globalString, type)
      }
      throw IRError.unknownType("String with parts")
    case .formatString(let exprs, let type):
      let values: [(IRValue, StoredType)] = try exprs.map(emitExprAndLoad)
      let format = values.map(\.1.stringFormat).joined(separator: "")
      let formatPointer = module.insertGlobalStringPointer(format, name: "", at: currentInsertion)
      guard let sPrintf = module.function(named: "sprintf") else { throw IRError.unknownFunction("sprintf") }
      let outBuffer = module.insertMalloc(module.i8, count: module.i32.constant(1000), at: currentInsertion)
      _ = module.insertCall(sPrintf, on: [outBuffer, formatPointer] + values.map(\.0), at: currentInsertion)
      return (outBuffer, type)
    case .binary(let lhs, let op, let rhs, let type):
      let (lhsVal, _) = try emitExprAndLoad(expr: lhs)
      let (rhsVal, _) = try emitExprAndLoad(expr: rhs)
      let result: IRValue
      switch op {
      case .plus:
        if FloatingPointType(lhsVal.type) != nil {
          result = module.insertFAdd(lhsVal, rhsVal, at: currentInsertion)
        } else {
          result = module.insertAdd(lhsVal, rhsVal, at: currentInsertion)
        }
      case .minus:
        if FloatingPointType(lhsVal.type) != nil {
          result = module.insertFSub(lhsVal, rhsVal, at: currentInsertion)
        } else {
          result = module.insertSub(lhsVal, rhsVal, at: currentInsertion)
        }
      case .divide:
        if FloatingPointType(lhsVal.type) != nil {
          result = module.insertFDiv(lhsVal, rhsVal, at: currentInsertion)
        } else {
          result = module.insertUnsignedDiv(lhsVal, rhsVal, at: currentInsertion)
        }
      case .times:
        if FloatingPointType(lhsVal.type) != nil {
          result = module.insertFMul(lhsVal, rhsVal, at: currentInsertion)
        } else {
          result = module.insertMul(lhsVal, rhsVal, at: currentInsertion)
        }
      case .mod:
        if FloatingPointType(lhsVal.type) != nil {
          result = module.insertFRem(lhsVal, rhsVal, at: currentInsertion)
        } else {
          result = module.insertSignedRem(lhsVal, rhsVal, at: currentInsertion)
        }
      }
      return (result, type)
    case .logical(let lhs, let op, let rhs, let type):
      let (lhsVal, lhsType) = try emitExprAndLoad(expr: lhs)
      let (rhsVal, rhsType) = try emitExprAndLoad(expr: rhs)
      
      let lhsCond = try truthify(lhsVal, with: lhsType)
      let rhsCond = try truthify(rhsVal, with: rhsType)
      
      var comparisonType: (float: FloatingPointPredicate, int: IntegerPredicate)? = nil
      
      switch op {
      case .and:
        let intRes = module.insertBitwiseAnd(lhsCond, rhsCond, at: currentInsertion)
        return (intRes, type)
      case .or:
        let intRes = module.insertBitwiseOr(lhsCond, rhsCond, at: currentInsertion)
        return (intRes, type)
      case .equals:
        comparisonType = (.oeq, .eq)
      case .notEqual:
        comparisonType = (.one, .ne)
      case .lessThan:
        comparisonType = (.olt, .slt)
      case .lessThanOrEqual:
        comparisonType = (.ole, .sle)
      case .greaterThan:
        comparisonType = (.ogt, .sgt)
      case .greaterThanOrEqual:
        comparisonType = (.oge, .sge)
      }
      if lhsVal.type is FloatingPointType,
        rhsVal.type is FloatingPointType {
        return (module.insertFloatingPointComparison( comparisonType!.float, lhsVal, rhsVal, at: currentInsertion), type)
      }
      if lhsVal.type is IntegerType,
        rhsVal.type is IntegerType {
        return (module.insertIntegerComparison(comparisonType!.int, lhsVal, rhsVal, at: currentInsertion), type)
      }
      throw IRError.unableToCompare(lhsVal.type, rhsVal.type)
      
    case .call(let functionCall, let type):
      guard let prototype = try? callables.findVariable(name: functionCall.name) else {
        throw IRError.unknownFunction(functionCall.name)
      }
      guard prototype.params.count == functionCall.args.count else {
        throw IRError.wrongNumberOfArgs(functionCall.name,
                                        expected: prototype.params.count,
                                        got: functionCall.args.count)
      }
      try zip(prototype.params, functionCall.args).forEach { (protoArg, callArg) in
        if protoArg.name != callArg.label {
          throw IRError.incorrectFunctionLabel(prototype.name,
                                               expected: protoArg.name,
                                               got: callArg.label ?? "")
        }
      }
      let callArgs = try functionCall.args.map{$0.typedExpr}.map(emitExprAndLoad).map { $0.0 }
      let function = try emitPrototype(prototype)
      return (module.insertCall(function, on: callArgs, at: currentInsertion), type)
    case .return(let expr, let type):
      guard let returnBlock = currentReturnBlock else {
        throw IRError.returnOutsideFunction
      }
      if let expr = expr {
        let (innerVal, _) = try emitExprAndLoad(expr: expr)
        let returnVar = try parameterValues.findVariable(name: ".return")
        module.insertStore(innerVal, to: returnVar, at: currentInsertion)
      }
      return (module.insertBr(to: returnBlock, at: currentInsertion), type)
    case .ifelse(let cond, let thenBlock, let elseBlock, let type):
      let (condition, conditionType) = try emitExprAndLoad(expr: cond)
      let truthCondition = try truthify(condition, with: conditionType)
      let checkCond = module.insertIntegerComparison(.ne, truthCondition, (truthCondition.type as! IntegerType).zero, at: currentInsertion)
      
      let thenBB = module.appendBlock(named: "then", to: currentFunction)
      let elseBB = module.appendBlock(named: "else", to: currentFunction)
      let mergeBB = module.appendBlock(named: "merge", to: currentFunction)
      
      module.insertCondBr(if: checkCond, then: thenBB, else: elseBB, at: currentInsertion)
      
      currentInsertion = module.endOf(thenBB)
      try thenBlock.forEach { let _ = try emitExpr($0) }
      if case .return = thenBlock.last {
        // No need to branch because we already returned
      } else {
        module.insertBr(to: mergeBB, at: currentInsertion)
      }
      
      currentInsertion = module.endOf(elseBB)
      try elseBlock.forEach { let _ = try emitExpr($0) }
      if case .return = elseBlock.last {
        // No need to branch because we already returned
      } else {
        module.insertBr(to: mergeBB, at: currentInsertion)
      }
      
      currentInsertion = module.endOf(mergeBB)
      
      return (Undefined(of: module.void), type)
    case .forLoop(let ass, let cond, let body, let type):
      parameterValues.startFrame()
      defer {
        parameterValues.endFrame()
      }
      let startBB = module.appendBlock(named: "setup", to: currentFunction)
      let bodyBB = module.appendBlock(named: "body", to: currentFunction)
      let cleanupBB = module.appendBlock(named: "cleanup", to: currentFunction)
      
      module.insertBr(to: startBB, at: currentInsertion)
      
      currentInsertion = module.endOf(startBB)
      let _ = try emitExpr(ass)
      let (startCondition, startConditionType) = try emitExpr(cond)
      let startTruthCondition = try truthify(startCondition, with: startConditionType)
      let startCheckCond = module.insertIntegerComparison(.ne, startTruthCondition, (startTruthCondition.type as! IntegerType).zero, at: currentInsertion)
      module.insertCondBr(if: startCheckCond, then: bodyBB, else: cleanupBB, at: currentInsertion)

      
      currentInsertion = module.endOf(bodyBB)
      try body.forEach { let _ = try emitExpr($0) }
      let (endCondition, endConditionType) = try emitExpr(cond)
      let endTruthCondition = try truthify(endCondition, with: endConditionType)
      let endCheckCond = module.insertIntegerComparison(.ne, endTruthCondition, (endTruthCondition.type as! IntegerType).zero, at: currentInsertion)
      module.insertCondBr(if: endCheckCond, then: bodyBB, else: cleanupBB, at: currentInsertion)
      currentInsertion = module.endOf(cleanupBB)
      
      return (Undefined(of: module.void), type)
    case .whileLoop(let cond, let body, let type):
      parameterValues.startFrame()
      defer {
        parameterValues.endFrame()
      }
      let startBB = module.appendBlock(named: "setup", to: currentFunction)
      let bodyBB = module.appendBlock(named: "body", to: currentFunction)
      let cleanupBB = module.appendBlock(named: "cleanup", to: currentFunction)
      
      module.insertBr(to: startBB, at: currentInsertion)
      let (startCondition, startConditionType) = try emitExpr(cond)
      let startTruthCondition = try truthify(startCondition, with: startConditionType)
      let startCheckCond = module.insertIntegerComparison(.ne, startTruthCondition, (startTruthCondition.type as! IntegerType).zero, at: currentInsertion)
      module.insertCondBr(if: startCheckCond, then: bodyBB, else: cleanupBB, at: currentInsertion)
      
      currentInsertion = module.endOf(bodyBB)
      try body.forEach { let _ = try emitExpr($0) }
      let (endCondition, endConditionType) = try emitExpr(cond)
      let endTruthCondition = try truthify(endCondition, with: endConditionType)
      let endCheckCond = module.insertIntegerComparison(.ne, endTruthCondition, (endTruthCondition.type as! IntegerType).zero, at: currentInsertion)
      module.insertCondBr(if: endCheckCond, then: bodyBB, else: cleanupBB, at: currentInsertion)
      currentInsertion = module.endOf(cleanupBB)
      
      return (Undefined(of: module.void), type)
    }
  }
  
  func emitExprAndLoad(expr: TypedExpr) throws -> (IRValue, StoredType) {
    let (reference, refType) = try emitExpr(expr)
    let loaded = try value(from: reference, with: refType)
    return loaded
  }
  
  func value(from variable: IRValue, with expectedType: StoredType) throws -> (IRValue, StoredType) {
    guard let loadedType = try expectedType.loadedRef(types: typesByName, in: &module) else {
      return (variable, expectedType)
    }
    guard let referencedType = (expectedType as? ReferenceStore)?.pointee else {
      return (variable, expectedType)
    }
    return (module.insertLoad(loadedType, from: variable, at: currentInsertion), referencedType)
  }
  
  func stringPrintFormat() -> IRValue {
    guard let format = module.global(named: "StringPrintFormat") else {
      return module.insertGlobalStringPointer("%s\n", name: "StringPrintFormat", at: currentInsertion)
    }
    let stringType = PointerType(pointee: IntegerType(8, in: &module), in: &module)
    return module.insertGetConstantElementPointer(of: format, typed: stringType, indices: [module.i1.zero, module.i1.zero])
  }
  
  func truthify(_ val: IRValue, with type: StoredType) throws -> IRValue {
    let (loadedValue, _) = try value(from: val, with: type)
    return try loadedValue.truthify(at: currentInsertion, in: &module)
  }
}

extension StoredType {
  func findType(types: [String: CallableType], in module: Module) throws -> IRType {
    self.module = module
    if let type = IRType {
      return type
    }
    guard let typeDef = types[name],
          let type = typeDef.IRType else {
      throw IRError.unknownType(name)
    }
    IRType = type
    return type
  }
  
  func findRef(types: [String: CallableType], in module: Module) throws -> IRType {
    self.module = module
    if let ref = IRRef {
      return ref
    }
    guard let typeDef = types[name],
          let ref = typeDef.IRRef else {
      throw IRError.unknownType(name)
    }
    IRRef = ref
    return ref
  }
  
  func loadedType(types: [String: any CallableType], in module: inout Module) throws -> IRType? {
    nil
  }
  
  func loadedRef(types: [String: any CallableType], in module: inout Module) throws -> IRType? {
    nil
  }
  
  var resolvedType: any StoredType {
    self
  }
}

extension IRValue {
  func truthify(at p: InsertionPoint, in module: inout Module) throws -> IRValue {
    if let truthVal = self.type.truthify(value: self, at: p, in: &module) {
      return truthVal
    }
    throw IRError.nonTruthyType(self.type)
  }
}

extension IRType {
  func truthify(value: IRValue, at p: InsertionPoint, in module: inout Module) -> IRValue? {
    if let truthable = self as? Truthable {
      return truthable.truthy(value: value, at: p, in: &module)
    }
    return nil
  }
}

protocol Truthable {
  func truthy(value: IRValue, at p: InsertionPoint, in module: inout Module) -> IRValue
}

extension FloatingPointType: Truthable {
  func truthy(value: IRValue, at p: InsertionPoint, in module: inout Module) -> IRValue {
    return module.insertFPtoInt(value, to: module.i1, signed: false, at: p)
  }
}

extension IntegerType: Truthable {
  func truthy(value: IRValue, at p: InsertionPoint, in module: inout Module) -> IRValue {
    return value
  }
}

protocol Printable {
  func printFormat(module: inout Module, at p: InsertionPoint) -> IRValue
}

extension IntegerType: Printable {
  func printFormat(module: inout Module, at p: InsertionPoint) -> IRValue {
    guard let format = module.global(named: "IntPrintFormat") else {
      return module.insertGlobalStringPointer("%d\n", name: "IntPrintFormat", at: p)
    }
    let stringType = PointerType(pointee: IntegerType(8, in: &module), in: &module)
    return module.insertGetConstantElementPointer(of: format, typed: stringType, indices: [module.i1.zero, module.i1.zero])
  }
}

extension FloatingPointType: Printable {
  func printFormat(module: inout Module, at p: InsertionPoint) -> IRValue {
    guard let format = module.global(named: "FloatPrintFormat") else {
      return module.insertGlobalStringPointer("%f\n", name: "FloatPrintFormat", at: p)
    }
    let stringType = PointerType(pointee: IntegerType(8, in: &module), in: &module)
    return module.insertGetConstantElementPointer(of: format, typed: stringType, indices: [module.i1.zero, module.i1.zero])
  }
}

