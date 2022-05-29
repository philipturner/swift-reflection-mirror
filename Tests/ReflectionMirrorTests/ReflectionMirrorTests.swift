import XCTest
@_spi(Reflection) import ReflectionMirror

final class ReflectionMirrorTests: XCTestCase {
  func testExample() throws {
    // This is an example of a functional test case.
    // Use XCTAssert and related functions to verify your tests produce the correct
    // results.
    _ = _EachFieldOptions.self
    _ = _forEachField(of:options:body:)
  }
  
  func testStruct() throws {
    struct MyStruct {
      var x: Int
      var y: Double
      var z: Bool?
      var w: Int16
      
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
  }
}
