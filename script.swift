import Swift

import SwiftShims

struct MyStruct {
  var x: Int
  var y: Double
  var z: Bool?
  var w: Int16
}

//_forEachFieldWithKeyPath(of: MyStruct.self, options: .ignoreUnknown) { name, kp in
//  print(String(cString: name))
//  print(kp)
//  return true
//}

print("barrier ---------")

//_forEachField(of: MyStruct.self, options: .ignoreUnknown) { name, offset, childType, kind in
//  print(String(cString: name))
//  print(offset)
//  print(childType)
//  print(kind)
//  return true
//}

let type: Any.Type = MyStruct.self
let options: _EachFieldOptions = []
let body: (UnsafePointer<CChar>, Int, Any.Type, _MetadataKind) -> Bool = { name, offset, childType, kind in
  print(String(cString: name))
  print(offset)
  print(childType)
  print(kind)
  return true
}

typealias Root = MyStruct
let body2: (UnsafePointer<CChar>, PartialKeyPath<Root>) -> Bool = { name, kp in
  print(String(cString: name))
  print(kp)
  return true
}

public struct _EachFieldOptions: OptionSet {
  public var rawValue: UInt32

  public init(rawValue: UInt32) {
    self.rawValue = rawValue
  }

  /// Require the top-level type to be a class.
  ///
  /// If this is not set, the top-level type is required to be a struct or
  /// tuple.
  public static var classType = _EachFieldOptions(rawValue: 1 << 0)

  /// Ignore fields that can't be introspected.
  ///
  /// If not set, the presence of things that can't be introspected causes
  /// the function to immediately return `false`.
  public static var ignoreUnknown = _EachFieldOptions(rawValue: 1 << 1)
}

@_silgen_name("swift_isClassType")
internal func _isClassType(_: Any.Type) -> Bool

@_silgen_name("swift_getMetadataKind")
internal func _metadataKind(_: Any.Type) -> UInt

@_silgen_name("swift_reflectionMirror_recursiveCount")
internal func _getRecursiveChildCount(_: Any.Type) -> Int

@_silgen_name("swift_reflectionMirror_recursiveChildMetadata")
internal func _getChildMetadata(
  _: Any.Type,
  index: Int,
  fieldMetadata: UnsafeMutablePointer<_FieldReflectionMetadata>
) -> Any.Type

@_silgen_name("swift_reflectionMirror_recursiveChildOffset")
internal func _getChildOffset(
  _: Any.Type,
  index: Int
) -> Int

public enum _MetadataKind: UInt {
  // With "flags":
  // runtimePrivate = 0x100
  // nonHeap = 0x200
  // nonType = 0x400
  
  case `class` = 0
  case `struct` = 0x200     // 0 | nonHeap
  case `enum` = 0x201       // 1 | nonHeap
  case optional = 0x202     // 2 | nonHeap
  case foreignClass = 0x203 // 3 | nonHeap
  case opaque = 0x300       // 0 | runtimePrivate | nonHeap
  case tuple = 0x301        // 1 | runtimePrivate | nonHeap
  case function = 0x302     // 2 | runtimePrivate | nonHeap
  case existential = 0x303  // 3 | runtimePrivate | nonHeap
  case metatype = 0x304     // 4 | runtimePrivate | nonHeap
  case objcClassWrapper = 0x305     // 5 | runtimePrivate | nonHeap
  case existentialMetatype = 0x306  // 6 | runtimePrivate | nonHeap
  case heapLocalVariable = 0x400    // 0 | nonType
  case heapGenericLocalVariable = 0x500 // 0 | nonType | runtimePrivate
  case errorObject = 0x501  // 1 | nonType | runtimePrivate
  case unknown = 0xffff
  
  init(_ type: Any.Type) {
    let v = _metadataKind(type)
    if let result = _MetadataKind(rawValue: v) {
      self = result
    } else {
      self = .unknown
    }
  }
}

func _withClassAsPointer<T: AnyObject>(
  _ input: T,
  _ body: (UnsafeMutableRawPointer) -> Void
) {
  // Program will crash if I retain/release the pointer, so just leave it
  // un-retained.
  let unmanaged = Unmanaged.passUnretained(input)
  body(unmanaged.toOpaque())
}

extension AnyKeyPath {
  internal static func _create(
    capacityInBytes bytes: Int,
    initializedBy body: (UnsafeMutableRawBufferPointer) -> Void
  ) -> Self {
    precondition(bytes > 0 && bytes % 4 == 0,
     "capacity must be multiple of 4 bytes")
    let result = Builtin.allocWithTailElems_1(
      self, (bytes/4)._builtinWordValue, Int32.self)
    
    // Workaround for the fact that `_kvcKeyPathStringPtr` is API-internal.
    // Emulates the code: `result._kvcKeyPathStringPtr = nil`
    _withClassAsPointer(result) { opaque in
      let propertyType = UnsafePointer<CChar>?.self
      let bound = opaque.assumingMemoryBound(to: propertyType)
      bound.pointee = nil
      print("Original pointer:", opaque)
    }
    
    let base = UnsafeMutableRawPointer(
      Builtin.projectTailElems(result, Int32.self))
    let bufferPointer = UnsafeMutableRawBufferPointer(start: base, count: bytes)
    print("Second pointer:", bufferPointer)
    body(bufferPointer)
    print("Finished _create")
    return result
  }
}

internal struct KeyPathBuffer {
  internal struct Builder {
    internal var buffer: UnsafeMutableRawBufferPointer
    internal init(_ buffer: UnsafeMutableRawBufferPointer) {
      self.buffer = buffer
    }
  }
}

internal struct RawKeyPathComponent {
  internal struct Header {
    // The component header is 4 bytes, but may be followed by an aligned
    // pointer field for some kinds of component, forcing padding.
    internal static var pointerAlignmentSkew: Int {
      return MemoryLayout<Int>.size - MemoryLayout<Int32>.size
    }
  }
}

func my_forEachField() -> Bool {
  // Class types not supported because the metadata does not have
  // enough information to construct computed properties.
  if _isClassType(type) != options.contains(.classType) {
    return false
  }
  let ignoreUnknown = options.contains(.ignoreUnknown)
  
  let childCount = _getRecursiveChildCount(type)
  for i in 0..<childCount {
    let offset = _getChildOffset(type, index: i)

    var field = _FieldReflectionMetadata()
    let childType = _getChildMetadata(type, index: i, fieldMetadata: &field)
    defer { field.freeFunc?(field.name) }
    let kind = _MetadataKind(childType)
    let supportedType: Bool
    switch kind {
      case .struct, .class, .optional, .existential,
          .existentialMetatype, .tuple, .enum:
        supportedType = true
      default:
        supportedType = false
    }
    if !supportedType || !field.isStrong {
      if !ignoreUnknown { return false }
      continue;
    }
    func keyPathType<Leaf>(for: Leaf.Type) -> PartialKeyPath<MyStruct>.Type {
      if field.isVar { return WritableKeyPath<MyStruct, Leaf>.self }
      return KeyPath<MyStruct, Leaf>.self
    }
    let resultSize = MemoryLayout<Int32>.size + MemoryLayout<Int>.size
    let partialKeyPathType = _openExistential(childType, do: keyPathType)
      ._create(capacityInBytes: resultSize, initializedBy: { _ in
        
      })
    
    
    
    

//    if !body(field.name!, offset, childType, kind) {
//      return false
//    }
  }
  return true
}

print(my_forEachField())
