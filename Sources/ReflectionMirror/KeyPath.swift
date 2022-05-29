//
//  KeyPath.swift
//  
//
//  Created by Philip Turner on 5/29/22.
//

import SwiftShims

// A way to emulate the behavior of `Builtin.projectTailElems` without actually
// calling that function. Treat the class like a pointer to a pointer, then
// increment the second-level pointer by `tailAllocOffset`. This is used in
// `AnyKeyPath._create`.
//
// On development toolchains, using `Builtin.projectTailElems` causes a compiler
// crash (see https://github.com/apple/swift/issues/59118 for more info). On
// release toolchains, it strangely does a 16-byte offset instead of the correct
// 24-byte offset (why?). I have not tested this on 32-bit platforms, but I
// assume the 24-byte offset is just 3 pointers.
internal let tailAllocOffset = 3 * MemoryLayout<Int>.stride

extension AnyKeyPath {
  internal static func _create(
    capacityInBytes bytes: Int,
    initializedBy body: (UnsafeMutableRawBufferPointer) -> Void
  ) -> Self {
    _internalInvariant(bytes > 0 && bytes % 4 == 0,
                 "capacity must be multiple of 4 bytes \(bytes)")
    let result = Builtin.allocWithTailElems_1(self, (bytes/4)._builtinWordValue,
                                              Int32.self)

    // The following line from the Swift stdlib is not implemented. Trying to
    // erase this pointer causes a crash when running Swift package tests:
    //
//    result._kvcKeyPathStringPtr = nil

    // Also, the docs say it's only used for Foundation overlays. The commit
    // adding the line (linked below) was solely for Objective-C interop. We are
    // not building Foundation here, so there should be no problem with leaving
    // `_kvcKeyPathStringPtr` as non-`nil`.
    //
    // Doc comment for `_kvcKeyPathString`:
    // // SPI for the Foundation overlay to allow interop with KVC keypath-based
    // // APIs.
    //
    // Commit:
    // https://github.com/apple/swift/commit/d5cdf658daa7754b8938e671b7d5a80590eb106c

    // There was an instance where `_kvcKeyPathString` was non-nil for the
    // `AnyObject` type (Swift 5.6.1, arm64 macOS, during package tests). I have
    // not reproduced it yet, and I don't know whether it's a serious problem.
//    precondition(result._kvcKeyPathString == nil, """
//      ReflectionMirror has not accounted for the case where _kvcKeyPathString \
//      is non-nil. Please submit an issue to https://github.com/philipturner/\
//      swift-reflection-mirror.
//      """)

    let unmanaged = Unmanaged.passUnretained(result)
    let base = unmanaged.toOpaque().advanced(by: tailAllocOffset)
//    let base = UnsafeMutableRawPointer(Builtin.projectTailElems(result,
//                                                                Int32.self))
    body(UnsafeMutableRawBufferPointer(start: base, count: bytes))
    return result
  }

}

// MARK: Implementation details

internal enum KeyPathComponentKind {
  /// The keypath references an externally-defined property or subscript whose
  /// component describes how to interact with the key path.
  case external
  /// The keypath projects within the storage of the outer value, like a
  /// stored property in a struct.
  case `struct`
  /// The keypath projects from the referenced pointer, like a
  /// stored property in a class.
  case `class`
  /// The keypath projects using a getter/setter pair.
  case computed
  /// The keypath optional-chains, returning nil immediately if the input is
  /// nil, or else proceeding by projecting the value inside.
  case optionalChain
  /// The keypath optional-forces, trapping if the input is
  /// nil, or else proceeding by projecting the value inside.
  case optionalForce
  /// The keypath wraps a value in an optional.
  case optionalWrap
}

internal struct RawKeyPathComponent {
  internal var header: Header
  internal var body: UnsafeRawBufferPointer

  internal init(header: Header, body: UnsafeRawBufferPointer) {
    self.header = header
    self.body = body
  }
  
  internal struct Header {
    internal var _value: UInt32
    
    init(discriminator: UInt32, payload: UInt32) {
      _value = 0
      self.discriminator = discriminator
      self.payload = payload
    }
    
    internal var discriminator: UInt32 {
      get {
        return (_value & Header.discriminatorMask) >> Header.discriminatorShift
      }
      set {
        let shifted = newValue << Header.discriminatorShift
        _internalInvariant(shifted & Header.discriminatorMask == shifted,
                     "discriminator doesn't fit")
        _value = _value & ~Header.discriminatorMask | shifted
      }
    }
    internal var storedOffsetPayload: UInt32 {
      get {
        _internalInvariant(kind == .struct || kind == .class,
                     "not a stored component")
        return _value & Header.storedOffsetPayloadMask
      }
      set {
        _internalInvariant(kind == .struct || kind == .class,
                     "not a stored component")
        _internalInvariant(newValue & Header.storedOffsetPayloadMask == newValue,
                     "payload too big")
        _value = _value & ~Header.storedOffsetPayloadMask | newValue
      }
    }
    internal var payload: UInt32 {
      get {
        return _value & Header.payloadMask
      }
      set {
        _internalInvariant(newValue & Header.payloadMask == newValue,
                     "payload too big")
        _value = _value & ~Header.payloadMask | newValue
      }
    }
    internal var endOfReferencePrefix: Bool {
      get {
        return _value & Header.endOfReferencePrefixFlag != 0
      }
      set {
        if newValue {
          _value |= Header.endOfReferencePrefixFlag
        } else {
          _value &= ~Header.endOfReferencePrefixFlag
        }
      }
    }
    
    internal var kind: KeyPathComponentKind {
      switch (discriminator, payload) {
      case (Header.externalTag, _):
        return .external
      case (Header.structTag, _):
        return .struct
      case (Header.classTag, _):
        return .class
      case (Header.computedTag, _):
        return .computed
      case (Header.optionalTag, Header.optionalChainPayload):
        return .optionalChain
      case (Header.optionalTag, Header.optionalWrapPayload):
        return .optionalWrap
      case (Header.optionalTag, Header.optionalForcePayload):
        return .optionalForce
      default:
        _internalInvariantFailure("invalid header")
      }
    }
    
    internal static var payloadMask: UInt32 {
      return _SwiftKeyPathComponentHeader_PayloadMask
    }
    internal static var discriminatorMask: UInt32 {
      return _SwiftKeyPathComponentHeader_DiscriminatorMask
    }
    internal static var discriminatorShift: UInt32 {
      return _SwiftKeyPathComponentHeader_DiscriminatorShift
    }
    internal static var externalTag: UInt32 {
      return _SwiftKeyPathComponentHeader_ExternalTag
    }
    internal static var structTag: UInt32 {
      return _SwiftKeyPathComponentHeader_StructTag
    }
    internal static var computedTag: UInt32 {
      return _SwiftKeyPathComponentHeader_ComputedTag
    }
    internal static var classTag: UInt32 {
      return _SwiftKeyPathComponentHeader_ClassTag
    }
    internal static var optionalTag: UInt32 {
      return _SwiftKeyPathComponentHeader_OptionalTag
    }
    internal static var optionalChainPayload: UInt32 {
      return _SwiftKeyPathComponentHeader_OptionalChainPayload
    }
    internal static var optionalWrapPayload: UInt32 {
      return _SwiftKeyPathComponentHeader_OptionalWrapPayload
    }
    internal static var optionalForcePayload: UInt32 {
      return _SwiftKeyPathComponentHeader_OptionalForcePayload
    }
    
    internal static var endOfReferencePrefixFlag: UInt32 {
      return _SwiftKeyPathComponentHeader_EndOfReferencePrefixFlag
    }
    internal static var storedMutableFlag: UInt32 {
      return _SwiftKeyPathComponentHeader_StoredMutableFlag
    }
    internal static var storedOffsetPayloadMask: UInt32 {
      return _SwiftKeyPathComponentHeader_StoredOffsetPayloadMask
    }
    internal static var outOfLineOffsetPayload: UInt32 {
      return _SwiftKeyPathComponentHeader_OutOfLineOffsetPayload
    }
    internal static var unresolvedFieldOffsetPayload: UInt32 {
      return _SwiftKeyPathComponentHeader_UnresolvedFieldOffsetPayload
    }
    internal static var unresolvedIndirectOffsetPayload: UInt32 {
      return _SwiftKeyPathComponentHeader_UnresolvedIndirectOffsetPayload
    }
    internal static var maximumOffsetPayload: UInt32 {
      return _SwiftKeyPathComponentHeader_MaximumOffsetPayload
    }
    
    // The component header is 4 bytes, but may be followed by an aligned
    // pointer field for some kinds of component, forcing padding.
    internal static var pointerAlignmentSkew: Int {
      return MemoryLayout<Int>.size - MemoryLayout<Int32>.size
    }
    
    init(stored kind: KeyPathStructOrClass,
         mutable: Bool,
         inlineOffset: UInt32) {
      let discriminator: UInt32
      switch kind {
      case .struct: discriminator = Header.structTag
      case .class: discriminator = Header.classTag
      }

      _internalInvariant(inlineOffset <= Header.maximumOffsetPayload)
      let payload = inlineOffset
        | (mutable ? Header.storedMutableFlag : 0)
      self.init(discriminator: discriminator,
                payload: payload)
    }
  }
  
  internal func clone(into buffer: inout UnsafeMutableRawBufferPointer,
             endOfReferencePrefix: Bool) {
    var newHeader = header
    newHeader.endOfReferencePrefix = endOfReferencePrefix
    
    var componentSize = MemoryLayout<Header>.size
    buffer.storeBytes(of: newHeader, as: Header.self)
    switch header.kind {
    case .struct,
         .class:
      if header.storedOffsetPayload == Header.outOfLineOffsetPayload {
        let overflowOffset = body.load(as: UInt32.self)
        buffer.storeBytes(of: overflowOffset, toByteOffset: 4,
                          as: UInt32.self)
        componentSize += 4
      }
      break
    case .optionalChain,
         .optionalForce,
         .optionalWrap:
      break
    case .computed:
      // Metadata does not have enough information to construct computed
      // properties. In the Swift stdlib, this case would trigger a large block
      // of code. That code is left out because it is not necessary.
      fatalError("Implement support for key paths to computed properties.")
      break
    case .external:
      _internalInvariantFailure("should have been instantiated away")
    }
    buffer = UnsafeMutableRawBufferPointer(
      start: buffer.baseAddress.unsafelyUnwrapped + componentSize,
      count: buffer.count - componentSize)
  }
}

internal struct KeyPathBuffer {
  internal struct Builder {
    internal var buffer: UnsafeMutableRawBufferPointer
    internal init(_ buffer: UnsafeMutableRawBufferPointer) {
      self.buffer = buffer
    }
    internal mutating func pushRaw(
      size: Int, alignment: Int
    ) -> UnsafeMutableRawBufferPointer {
      var baseAddress = buffer.baseAddress.unsafelyUnwrapped
      var misalign = Int(bitPattern: baseAddress) & (alignment - 1)
      if misalign != 0 {
        misalign = alignment - misalign
        baseAddress = baseAddress.advanced(by: misalign)
      }
      let result = UnsafeMutableRawBufferPointer(
        start: baseAddress,
        count: size)
      buffer = UnsafeMutableRawBufferPointer(
        start: baseAddress + size,
        count: buffer.count - size - misalign)
      return result
    }
    internal mutating func push<T>(_ value: T) {
      let buf = pushRaw(size: MemoryLayout<T>.size,
                        alignment: MemoryLayout<T>.alignment)
      buf.storeBytes(of: value, as: T.self)
    }
    internal mutating func pushHeader(_ header: Header) {
      push(header)
      // Start the components at pointer alignment
      _ = pushRaw(size: RawKeyPathComponent.Header.pointerAlignmentSkew,
             alignment: 4)
    }
  }
  
  internal struct Header {
    internal var _value: UInt32
    internal init(size: Int, trivial: Bool, hasReferencePrefix: Bool) {
      _internalInvariant(size <= Int(Header.sizeMask),
                   "key path too big")
      _value = UInt32(size)
        | (trivial ? Header.trivialFlag : 0)
        | (hasReferencePrefix ? Header.hasReferencePrefixFlag : 0)
    }
    
    internal static var sizeMask: UInt32 {
      return _SwiftKeyPathBufferHeader_SizeMask
    }
    internal static var reservedMask: UInt32 {
      return _SwiftKeyPathBufferHeader_ReservedMask
    }
    internal static var trivialFlag: UInt32 {
      return _SwiftKeyPathBufferHeader_TrivialFlag
    }
    internal static var hasReferencePrefixFlag: UInt32 {
      return _SwiftKeyPathBufferHeader_HasReferencePrefixFlag
    }
  }
}

internal enum KeyPathStructOrClass {
  case `struct`, `class`
}
