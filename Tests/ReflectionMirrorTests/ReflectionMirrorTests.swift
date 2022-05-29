import XCTest
@_spi(Reflection) import Swift
@testable import ReflectionMirror

final class ReflectionMirrorTests: XCTestCase {
  func testSPISymbolsExist() {
    // This is an example of a functional test case.
    // Use XCTAssert and related functions to verify your tests produce the correct
    // results.
    _ = _EachFieldOptions.self
    _ = _EachFieldOptions.classType
    _ = _EachFieldOptions.ignoreUnknown
    
    _ = _MetadataKind.self
    _ = _MetadataKind.`class`
    _ = _MetadataKind.`struct`
    _ = _MetadataKind.`enum`
    _ = _MetadataKind.optional
    _ = _MetadataKind.foreignClass
    _ = _MetadataKind.opaque
    _ = _MetadataKind.tuple
    _ = _MetadataKind.function
    _ = _MetadataKind.existential
    _ = _MetadataKind.metatype
    _ = _MetadataKind.objcClassWrapper
    _ = _MetadataKind.existentialMetatype
    _ = _MetadataKind.heapLocalVariable
    _ = _MetadataKind.heapGenericLocalVariable
    _ = _MetadataKind.errorObject
    _ = _MetadataKind.unknown
    
    #if swift(>=5.2)
    _ = _forEachField
    #endif
    
    // `_forEachFieldWithKeyPath` must be specified with a generic signature.
    struct Factory<Root> {
      typealias Function = (Root.Type, _EachFieldOptions,
        (UnsafePointer<CChar>, PartialKeyPath<Root>) -> Bool) -> Bool
    }
    
    #if swift(>=5.4)
    _ = _forEachFieldWithKeyPath as Factory<Int>.Function
    _ = _forEachFieldWithKeyPath as Factory<String>.Function
    _ = _forEachFieldWithKeyPath as Factory<PartialKeyPath<Int>>.Function
    _ = _forEachFieldWithKeyPath as Factory<AnyObject>.Function
    #endif
    
    #if swift(>=5.6)
    _ = _forEachFieldWithKeyPath as Factory<any Sequence>.Function
    _ = _forEachFieldWithKeyPath as Factory<any Hashable>.Function
    #endif
  }
  
  #if swift(>=5.4)
  func testStruct()  {
    class MyClass {
      var q: Int
      var x: AnyObject
      init(q: Int, x: AnyObject) {
        self.q = q
        self.x = x
      }
    }
    
    struct MyStruct {
      var x: Int
      var y: String
      var z: Bool?
      var w: AnyObject
      var v: MyClass
      
      // Not iterated over
      var myComputed: Int32 {
        get { 9 }
        set { x = Int(newValue) }
      }
    }
    
    _forEachFieldWithKeyPath(of: MyStruct.self) { name, kp in
      print("A string:", String(cString: name))
      print("A kp:", kp)
      return true
    }
    
    // TODO: write to the keypaths
  }
  #endif
}
