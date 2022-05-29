//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import XCTest
@_spi(Reflection) import ReflectionMirror

struct TestStruct {
  var int = 0
  var double = 0.0
  var bool = false
}

struct GenericStruct<T> {
  var int = 0
  var first: T
  var second: T
}

enum TestEnum {
  case one
  case two
  case three(TestStruct)
}

class BaseClass {
  var superInt = 0
  init() {}
}

class TestClass: BaseClass {
  var int = 0
  var double = 0.0
  var bool = false
  override init() {}
}

class TestSubclass: TestClass {
  var strings: [String] = []
  override init() {}
}

class GenericClass<T, U>: BaseClass {
  var first: T
  var second: U

  init(_ t: T, _ u: U) {
    self.first = t
    self.second = u
  }
}

class GenericSubclass<V, W>: GenericClass<V, Bool> {
  var third: W

  init(_ v: V, _ w: W) {
    self.third = w
    super.init(v, false)
  }
}

class OwnershipTestClass: BaseClass {
  weak var test1: TestClass?
  unowned var test2: TestClass
  unowned(unsafe) var test3: TestClass
  
  init(_ t: TestClass) {
    self.test1 = t
    self.test2 = t
    self.test3 = t
  }
}

struct SimilarToNSPoint {
  var x: Double
  var y: Double
}

struct SimilarToNSSize {
  var width: Double
  var height: Double
}

struct SimilarToNSRect {
  var origin: SimilarToNSPoint
  var size: SimilarToNSSize
}

struct ContainsObject {
  var obj: TestClass
}

struct LetKeyPaths {
  let int : Int
  let double: Double
}

protocol TestExistential {}

struct KeyPathTypes {
  weak var weakObj: TestClass?
  unowned var unownedObj: TestClass
  var obj: TestClass
  var tuple: (Int, Int, Int)
  var structField: Int
  var function: (Int) -> (Int)
  var optionalFunction: (Int) -> (Int)?
  var enumField: TestEnum
  var existential: TestExistential
  var existentialMetatype: Any.Type
  var metatype: Int.Type
}

#if _runtime(_ObjC)
import Foundation

class NSObjectSubclass: NSObject {
  var point: (Double, Double)

  init(x: Double, y: Double) {
    self.point = (x, y)
  }
}

class EmptyNSObject: NSObject {}
#endif

@available(swift 5.2)
func checkFields<T>(
  of type: T.Type,
  options: _EachFieldOptions = [],
  fields: [String: (Int, Any.Type)]
) {
  var count = 0

  _forEachField(of: T.self, options: options) {
    charPtr, offset, type, kind in
    count += 1

    let fieldName = String(cString: charPtr)
    guard let (checkOffset, checkType) = fields[fieldName] else {
      XCTAssertTrue(false, "Unexpected field '\(fieldName)'")
      return true
    }

    XCTAssertEqual(checkOffset, offset)
    XCTAssertTrue(checkType == type)
    return true
  }

  XCTAssertEqual(fields.count, count)
}

@available(swift 5.5)
func checkFieldsWithKeyPath<T>(
  of type: T.Type,
  options: _EachFieldOptions = [],
  fields: [String: PartialKeyPath<T>]
) {
  var count = 0
  
//  for (key, value) in fields {
//    print("key: \(key)")
//    print("value: \(value)")
//    value.__inspect()
//    print()
//  }

  _forEachFieldWithKeyPath(of: T.self, options: options) {
    charPtr, keyPath in
    count += 1

    let fieldName = String(cString: charPtr)
    guard let checkKeyPath = fields[fieldName] else {
      XCTAssertTrue(false, "Unexpected field '\(fieldName)'")
      return true
    }

//    XCTAssertEqual(checkKeyPath, keyPath)
    XCTAssertTrue(checkKeyPath == keyPath, "\(checkKeyPath) ===== \(keyPath)")
    return true
  }

  XCTAssertEqual(fields.count, count)
}

protocol ExistentialProtocol {}

extension TestStruct: ExistentialProtocol {}
extension GenericStruct: ExistentialProtocol {}
extension GenericSubclass: ExistentialProtocol {}

@available(swift 5.2)
extension ExistentialProtocol {
  static func doCheckFields(
    options: _EachFieldOptions = [],
    fields: [String: (Int, Any.Type)]
  ) {
    checkFields(of: Self.self, options: options, fields: fields)
  }
}

@available(swift 5.2)
func checkFieldsAsExistential(
  of type: ExistentialProtocol.Type,
  options: _EachFieldOptions = [],
  fields: [String: (Int, Any.Type)]
) {
  type.doCheckFields(options: options, fields: fields)
}

@available(swift 5.2)
func _withTypeEncodingCallback(encoding: inout String, name: UnsafePointer<CChar>, offset: Int, type: Any.Type, kind: _MetadataKind) -> Bool {
  if type == Bool.self {
    encoding += "B"
    return true
  } else if type == Int.self {
    if MemoryLayout<Int>.size == MemoryLayout<Int64>.size {
      encoding += "q"
    } else if MemoryLayout<Int>.size == MemoryLayout<Int32>.size {
      encoding += "l"
    } else {
      return false
    }
    return true
  } else if type == Double.self {
    encoding += "d"
    return true
  }
  
  switch kind {
  case .struct:
    encoding += "{"
    defer { encoding += "}" }
    _forEachField(of: type) { name, offset, type, kind in
      _withTypeEncodingCallback(encoding: &encoding, name: name, offset: offset, type: type, kind: kind)
    }
  case .class:
    encoding += "@"
  default:
    break
  }
  return true
}

@available(swift 5.2)
func getTypeEncoding<T>(_ type: T.Type) -> String? {
  var encoding = ""
  _ = _forEachField(of: type) { name, offset, type, kind in
    _withTypeEncodingCallback(encoding: &encoding, name: name, offset: offset, type: type, kind: kind)
  }
  return "{\(encoding)}"
}

@available(swift 5.2)
func checkGenericStruct<T>(_: T.Type) {
  let firstOffset = max(MemoryLayout<Int>.stride, MemoryLayout<T>.alignment)
  
  checkFields(
    of: GenericStruct<T>.self,
    fields: [
      "int": (0, Int.self),
      "first": (firstOffset, T.self),
      "second": (firstOffset + MemoryLayout<T>.stride, T.self),
  ])

  checkFieldsAsExistential(
    of: GenericStruct<T>.self,
    fields: [
      "int": (0, Int.self),
      "first": (firstOffset, T.self),
      "second": (firstOffset + MemoryLayout<T>.stride, T.self),
  ])
}

//===----------------------------------------------------------------------===//

#if swift(>=5.2)
final class ForEachFieldTests: XCTestCase {
  func testTuple() {
    checkFields(
      of: (Int, Bool).self,
      fields: [".0": (0, Int.self), ".1": (MemoryLayout<Int>.stride, Bool.self)])

    checkFields(
      of: (a: Int, b: Bool).self,
      fields: ["a": (0, Int.self), "b": (MemoryLayout<Int>.stride, Bool.self)])
  }

  func testEnum() {
    checkFields(of: TestEnum.self, fields: [:])
  }

  func testStruct() {
    checkFields(
      of: TestStruct.self,
      fields: [
        "int": (0, Int.self),
        "double": (MemoryLayout<Double>.stride, Double.self),
        "bool": (MemoryLayout<Double>.stride * 2, Bool.self),
    ])

    checkFieldsAsExistential(
      of: TestStruct.self,
      fields: [
        "int": (0, Int.self),
        "double": (MemoryLayout<Double>.stride, Double.self),
        "bool": (MemoryLayout<Double>.stride * 2, Bool.self),
    ])

    // Applying to struct type with .classType option fails
    XCTAssertFalse(_forEachField(of: TestStruct.self, options: .classType) {
      _, _, _, _ in true
    })
  }

  #if swift(>=5.5)
  func testStructKeyPath() {
    checkFieldsWithKeyPath(
      of: TestStruct.self,
      fields: [
        "int": \TestStruct.int,
        "double": \TestStruct.double,
        "bool": \TestStruct.bool,
    ])
  }

  func testLetKeyPaths() {
    checkFieldsWithKeyPath(
      of: LetKeyPaths.self,
      fields: [
        "int": \LetKeyPaths.int,
        "double": \LetKeyPaths.double,
    ])
  }

  func testKeyPathTypes() {
    checkFieldsWithKeyPath(
      of: KeyPathTypes.self,
      options: .ignoreUnknown,
      fields: [
        "obj": \KeyPathTypes.obj,
        "tuple": \KeyPathTypes.tuple,
        "structField": \KeyPathTypes.structField,
        "enumField": \KeyPathTypes.enumField,
        "existential": \KeyPathTypes.existential,
        "existentialMetatype": \KeyPathTypes.existentialMetatype,
    ])
  }

  func testTupleKeyPath() {
    typealias TestTuple = (Int, Int, TestClass, TestStruct)
    checkFieldsWithKeyPath(
      of: TestTuple.self,
      fields: [
        ".0": \TestTuple.0,
        ".1": \TestTuple.1,
        ".2": \TestTuple.2,
        ".3": \TestTuple.3,
    ])
  }
  #endif

  func testGenericStruct() {
    checkGenericStruct(Bool.self)
    checkGenericStruct(TestStruct.self)
    checkGenericStruct((TestStruct, TestClass, Int, Int).self)
  }

  func testClass() {
    let classOffset = MemoryLayout<Int>.stride * 2
    let doubleOffset = classOffset
      + max(MemoryLayout<Int>.stride * 2, MemoryLayout<Double>.stride)

    checkFields(
      of: TestClass.self, options: .classType,
      fields: [
        "superInt": (classOffset, Int.self),
        "int": (classOffset + MemoryLayout<Int>.stride, Int.self),
        "double": (doubleOffset, Double.self),
        "bool": (doubleOffset + MemoryLayout<Double>.stride, Bool.self),
    ])

    checkFields(
      of: TestSubclass.self, options: .classType,
      fields: [
        "superInt": (classOffset, Int.self),
        "int": (classOffset + MemoryLayout<Int>.stride, Int.self),
        "double": (doubleOffset, Double.self),
        "bool": (doubleOffset + MemoryLayout<Double>.stride, Bool.self),
        "strings": (doubleOffset + MemoryLayout<Double>.stride + MemoryLayout<Array<String>>.stride, Array<String>.self),
    ])

    let firstOffset = classOffset
      + max(MemoryLayout<Int>.stride, MemoryLayout<TestStruct>.alignment)
    checkFields(
      of: GenericSubclass<TestStruct, TestStruct>.self, options: .classType,
      fields: [
        "superInt": (classOffset, Int.self),
        "first": (firstOffset, TestStruct.self),
        "second": (firstOffset + MemoryLayout<TestStruct>.size, Bool.self),
        "third": (firstOffset + MemoryLayout<TestStruct>.stride, TestStruct.self),
    ])

    checkFields(
      of: GenericSubclass<Int, Never>.self, options: .classType,
      fields: [
        "superInt": (classOffset, Int.self),
        "first": (classOffset + MemoryLayout<Int>.stride, Int.self),
        "second": (classOffset + MemoryLayout<Int>.stride * 2, Bool.self),
        "third": (0, Never.self),
    ])

    checkFieldsAsExistential(
      of: GenericSubclass<TestStruct, TestStruct>.self, options: .classType,
      fields: [
        "superInt": (classOffset, Int.self),
        "first": (firstOffset, TestStruct.self),
        "second": (firstOffset + MemoryLayout<TestStruct>.size, Bool.self),
        "third": (firstOffset + MemoryLayout<TestStruct>.stride, TestStruct.self),
    ])

    // Applying to class type without .classType option fails
    XCTAssertFalse(_forEachField(of: TestClass.self) {
      _, _, _, _ in true
    })
  }

  func testOwnershipTestClass() {
    let classOffset = MemoryLayout<Int>.stride * 2

    checkFields(
      of: OwnershipTestClass.self, options: .classType,
      fields: [
        "superInt": (classOffset, Int.self),
        "test1": (classOffset + MemoryLayout<Int>.stride, Optional<TestClass>.self),
        "test2": (classOffset + MemoryLayout<Int>.stride * 2, TestClass.self),
        "test3": (classOffset + MemoryLayout<Int>.stride * 3, TestClass.self),
    ])
  }

  #if _runtime(_ObjC)
  func testNSObjectSubclass() {
    XCTAssertTrue(_forEachField(of: NSObjectSubclass.self, options: .classType) {
      charPtr, _, type, _ in

      let fieldName = String(cString: charPtr)
      return type == (Double, Double).self
        && fieldName == "point"
    })

    XCTAssertTrue(_forEachField(of: EmptyNSObject.self, options: .classType) {
      _, _, _, _ in true
    })
  }
  #endif

  func testWithTypeEncoding() {
    XCTAssertEqual("{@}", getTypeEncoding(ContainsObject.self))
    XCTAssertEqual("{{dd}{dd}}", getTypeEncoding(SimilarToNSRect.self))
    
    let testEncoding = getTypeEncoding(TestStruct.self)
    XCTAssertTrue("{qdB}" == testEncoding || "{ldB}" == testEncoding)
  }
}
#endif
