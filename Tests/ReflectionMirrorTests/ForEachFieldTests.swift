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
