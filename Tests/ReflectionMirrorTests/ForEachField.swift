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
  
  _forEachFieldWithKeyPath(of: T.self, options: options) {
    charPtr, keyPath in
    count += 1

    let fieldName = String(cString: charPtr)
    guard let checkKeyPath = fields[fieldName] else {
      XCTAssertTrue(false, "Unexpected field '\(fieldName)'")
      return true
    }

    XCTAssertTrue(checkKeyPath == keyPath)
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
