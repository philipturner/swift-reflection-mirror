import XCTest
@_spi(Reflection) import ReflectionMirror
//@testable import ReflectionMirror

final class ReflectionMirrorTests: XCTestCase {
  func testSPISymbolsExist() {
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
  func testStruct() {
    struct Foo {
      var x: Int
      var y: String
      var z: Bool?
      var w: AnyObject
      var v: Bar
      var zx: Any.Type

      // Not iterated over
      var myComputed: Int32 {
        get { 9 }
        set { x = Int(newValue) }
      }
    }
    
    class Bar {
      var q: Int
      var x: AnyObject
      init(q: Int, x: AnyObject) {
        self.q = q
        self.x = x
      }
    }
    
    _forEachFieldWithKeyPath(of: Foo.self) { name, kp in
      print("A string:", String(cString: name))
      print("A kp:", kp)
      // Transform this into something that records the strings and ensures
      // they produce something sensible.
      return true
    }
  }
  
  func testModifyStruct() {
    struct Foo: Equatable {
      var x: Int = 1
      var y: Int = 2
      var z: Int = 3
    }
    
    var structToModify = Foo()
    
    _forEachFieldWithKeyPath(of: Foo.self, options: .ignoreUnknown) { _, kp in
      guard let writableKeyPath = kp as? WritableKeyPath<Foo, Int> else {
        XCTFail("Did not get a writable key path.")
        return false
      }
      structToModify[keyPath: writableKeyPath] = 4
      return true
    }
    
    XCTAssertEqual(structToModify, .init(x: 4, y: 4, z: 4))
  }
  #endif
}
