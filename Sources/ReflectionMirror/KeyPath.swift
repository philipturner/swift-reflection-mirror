//
//  KeyPath.swift
//  
//
//  Created by Philip Turner on 5/29/22.
//

import SwiftShims

// A way to emulate the behavior of `Builtin.projectTailElems` without actually
// calling that function. Treat the class like a pointer to a pointer, then
// increment the second-level pointer by `tailAllocOffset`.
//
// On development toolchains, using `Builtin.projectTailElems` causes a compiler
// crash (see https://github.com/apple/swift/issues/59118 for more info). On
// release toolchains, it strangely does a 16-byte offset instead of the correct
// 24-byte offset. I have not tested this on 32-bit platforms, but I assume the
// 24-byte offset is just 3 pointers.
let tailAllocOffset = 3 * MemoryLayout<Int>.stride

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
    // result._kvcKeyPathStringPtr = nil

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
    // not yet reproduced it, and I don't know whether it's a serious problem.
//    precondition(result._kvcKeyPathString == nil, """
//      ReflectionMirror has not accounted for the case where _kvcKeyPathString \
//      is non-nil. Please submit an issue to https://github.com/philipturner/\
//      swift-reflection-mirror.
//      """)

    let unmanaged = Unmanaged.passRetained(result)
    let opaque = unmanaged.toOpaque()
    print("opaque: \(opaque)")
    let bound_p = opaque.assumingMemoryBound(to: UnsafeMutableRawPointer.self)
    print("bound_p: \(bound_p.pointee)")
    let bound_s = opaque.assumingMemoryBound(to: UnsafePointer<CChar>.self)
    print("bound_s: \(String(cString: bound_s.pointee).utf8.map { $0 })")
    unmanaged.release()

    let base = opaque.advanced(by: tailAllocOffset)
//    let base = UnsafeMutableRawPointer(Builtin.projectTailElems(result,
//                                                                Int32.self))
    print("Getting bufptr")
    let bufptr = UnsafeMutableRawBufferPointer(start: base, count: bytes)
    print("bufptr: \(bufptr)")
    print("Finished getting bufptr")

    body(bufptr)
//    body(UnsafeMutableRawBufferPointer(start: base, count: bytes))
    return result
  }
  
  final internal func withBuffer2<T>(_ f: (KeyPathBuffer) throws -> T) rethrows -> T {
    defer { _fixLifetime(self) }
    
    let opaque = Unmanaged.passRetained(self).toOpaque()
    let base = UnsafeRawPointer(opaque).advanced(by: tailAllocOffset)
//    let base = UnsafeRawPointer(Builtin.projectTailElems(self, Int32.self))
    return try f(KeyPathBuffer(base: base))
  }
  
  public static func theyEqual(a: AnyKeyPath, b: AnyKeyPath) -> Bool {
    // Fast-path identical objects
    if a === b {
      return true
    }
    
    // Short-circuit differently-typed key paths
    if type(of: a) != type(of: b) {
      return false
    }
    return a.withBuffer2 {
      var aBuffer = $0
      return b.withBuffer2 {
        var bBuffer = $0

        // Two equivalent key paths should have the same reference prefix
        if aBuffer.hasReferencePrefix != bBuffer.hasReferencePrefix {
          return false
        }

        // Identity is equal to identity
        if aBuffer.data.isEmpty {
          return bBuffer.data.isEmpty
        }

        while true {
          let (aComponent, aType) = aBuffer.next()
          let (bComponent, bType) = bBuffer.next()

          if aComponent.header.endOfReferencePrefix
              != bComponent.header.endOfReferencePrefix
            || aComponent.value != bComponent.value
            || aType != bType {
            return false
          }
          if aType == nil {
            return true
          }
        }
      }
    }
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

internal struct ComputedPropertyID: Hashable {
  internal var value: Int
  internal var kind: KeyPathComputedIDKind

  internal static func ==(
    x: ComputedPropertyID, y: ComputedPropertyID
  ) -> Bool {
    return x.value == y.value
      && x.kind == y.kind
  }

  internal func hash(into hasher: inout Hasher) {
    hasher.combine(value)
    hasher.combine(kind)
  }
}

internal struct ComputedAccessorsPtr {
#if INTERNAL_CHECKS_ENABLED
  internal let header: RawKeyPathComponent.Header
#endif
  internal let _value: UnsafeRawPointer

  init(header: RawKeyPathComponent.Header, value: UnsafeRawPointer) {
#if INTERNAL_CHECKS_ENABLED
    self.header = header
#endif
    self._value = value
  }

  @_transparent
  static var getterPtrAuthKey: UInt64 {
    return UInt64(_SwiftKeyPath_ptrauth_Getter)
  }
  @_transparent
  static var nonmutatingSetterPtrAuthKey: UInt64 {
    return UInt64(_SwiftKeyPath_ptrauth_NonmutatingSetter)
  }
  @_transparent
  static var mutatingSetterPtrAuthKey: UInt64 {
    return UInt64(_SwiftKeyPath_ptrauth_MutatingSetter)
  }

  internal typealias Getter<CurValue, NewValue> = @convention(thin)
    (CurValue, UnsafeRawPointer, Int) -> NewValue
  internal typealias NonmutatingSetter<CurValue, NewValue> = @convention(thin)
    (NewValue, CurValue, UnsafeRawPointer, Int) -> ()
  internal typealias MutatingSetter<CurValue, NewValue> = @convention(thin)
    (NewValue, inout CurValue, UnsafeRawPointer, Int) -> ()

  internal var getterPtr: UnsafeRawPointer {
#if INTERNAL_CHECKS_ENABLED
    _internalInvariant(header.kind == .computed,
                 "not a computed property")
#endif
    return _value
  }
  internal var setterPtr: UnsafeRawPointer {
#if INTERNAL_CHECKS_ENABLED
    _internalInvariant(header.isComputedSettable,
                 "not a settable property")
#endif
    return _value + MemoryLayout<Int>.size
  }

  internal func getter<CurValue, NewValue>()
      -> Getter<CurValue, NewValue> {

    return getterPtr._loadAddressDiscriminatedFunctionPointer(
      as: Getter.self,
      discriminator: ComputedAccessorsPtr.getterPtrAuthKey)
  }

  internal func nonmutatingSetter<CurValue, NewValue>()
      -> NonmutatingSetter<CurValue, NewValue> {
#if INTERNAL_CHECKS_ENABLED
    _internalInvariant(header.isComputedSettable && !header.isComputedMutating,
                 "not a nonmutating settable property")
#endif

    return setterPtr._loadAddressDiscriminatedFunctionPointer(
      as: NonmutatingSetter.self,
      discriminator: ComputedAccessorsPtr.nonmutatingSetterPtrAuthKey)
  }

  internal func mutatingSetter<CurValue, NewValue>()
      -> MutatingSetter<CurValue, NewValue> {
#if INTERNAL_CHECKS_ENABLED
    _internalInvariant(header.isComputedSettable && header.isComputedMutating,
                 "not a mutating settable property")
#endif

    return setterPtr._loadAddressDiscriminatedFunctionPointer(
      as: MutatingSetter.self,
      discriminator: ComputedAccessorsPtr.mutatingSetterPtrAuthKey)
  }
}

internal struct ComputedArgumentWitnessesPtr {
  internal let _value: UnsafeRawPointer

  init(_ value: UnsafeRawPointer) {
    self._value = value
  }

  @_transparent
  static var destroyPtrAuthKey: UInt64 {
    return UInt64(_SwiftKeyPath_ptrauth_ArgumentDestroy)
  }
  @_transparent
  static var copyPtrAuthKey: UInt64 {
    return UInt64(_SwiftKeyPath_ptrauth_ArgumentCopy)
  }
  @_transparent
  static var equalsPtrAuthKey: UInt64 {
    return UInt64(_SwiftKeyPath_ptrauth_ArgumentEquals)
  }
  @_transparent
  static var hashPtrAuthKey: UInt64 {
    return UInt64(_SwiftKeyPath_ptrauth_ArgumentHash)
  }
  @_transparent
  static var layoutPtrAuthKey: UInt64 {
    return UInt64(_SwiftKeyPath_ptrauth_ArgumentLayout)
  }
  @_transparent
  static var initPtrAuthKey: UInt64 {
    return UInt64(_SwiftKeyPath_ptrauth_ArgumentInit)
  }

  internal typealias Destroy = @convention(thin)
    (_ instanceArguments: UnsafeMutableRawPointer, _ size: Int) -> ()
  internal typealias Copy = @convention(thin)
    (_ srcInstanceArguments: UnsafeRawPointer,
     _ destInstanceArguments: UnsafeMutableRawPointer,
     _ size: Int) -> ()
  internal typealias Equals = @convention(thin)
    (_ xInstanceArguments: UnsafeRawPointer,
     _ yInstanceArguments: UnsafeRawPointer,
     _ size: Int) -> Bool
  // FIXME(hasher) Combine to an inout Hasher instead
  internal typealias Hash = @convention(thin)
    (_ instanceArguments: UnsafeRawPointer,
     _ size: Int) -> Int

  // The witnesses are stored as address-discriminated authenticated
  // pointers.
  internal var destroy: Destroy? {
    return _value._loadAddressDiscriminatedFunctionPointer(
      as: Optional<Destroy>.self,
      discriminator: ComputedArgumentWitnessesPtr.destroyPtrAuthKey)
  }
  internal var copy: Copy {
    return _value._loadAddressDiscriminatedFunctionPointer(
      fromByteOffset: MemoryLayout<UnsafeRawPointer>.size,
      as: Copy.self,
      discriminator: ComputedArgumentWitnessesPtr.copyPtrAuthKey)
  }
  internal var equals: Equals {
    return _value._loadAddressDiscriminatedFunctionPointer(
      fromByteOffset: 2*MemoryLayout<UnsafeRawPointer>.size,
      as: Equals.self,
      discriminator: ComputedArgumentWitnessesPtr.equalsPtrAuthKey)
  }
  internal var hash: Hash {
    return _value._loadAddressDiscriminatedFunctionPointer(
      fromByteOffset: 3*MemoryLayout<UnsafeRawPointer>.size,
      as: Hash.self,
      discriminator: ComputedArgumentWitnessesPtr.hashPtrAuthKey)
  }
}

internal enum KeyPathComponent: Hashable {
  internal struct ArgumentRef {
    internal var data: UnsafeRawBufferPointer
    internal var witnesses: ComputedArgumentWitnessesPtr
    internal var witnessSizeAdjustment: Int

    internal init(
      data: UnsafeRawBufferPointer,
      witnesses: ComputedArgumentWitnessesPtr,
      witnessSizeAdjustment: Int
    ) {
      self.data = data
      self.witnesses = witnesses
      self.witnessSizeAdjustment = witnessSizeAdjustment
    }
  }

  /// The keypath projects within the storage of the outer value, like a
  /// stored property in a struct.
  case `struct`(offset: Int)
  /// The keypath projects from the referenced pointer, like a
  /// stored property in a class.
  case `class`(offset: Int)
  /// The keypath projects using a getter.
  case get(id: ComputedPropertyID,
           accessors: ComputedAccessorsPtr,
           argument: ArgumentRef?)
  /// The keypath projects using a getter/setter pair. The setter can mutate
  /// the base value in-place.
  case mutatingGetSet(id: ComputedPropertyID,
                      accessors: ComputedAccessorsPtr,
                      argument: ArgumentRef?)
  /// The keypath projects using a getter/setter pair that does not mutate its
  /// base.
  case nonmutatingGetSet(id: ComputedPropertyID,
                         accessors: ComputedAccessorsPtr,
                         argument: ArgumentRef?)
  /// The keypath optional-chains, returning nil immediately if the input is
  /// nil, or else proceeding by projecting the value inside.
  case optionalChain
  /// The keypath optional-forces, trapping if the input is
  /// nil, or else proceeding by projecting the value inside.
  case optionalForce
  /// The keypath wraps a value in an optional.
  case optionalWrap

  internal static func ==(a: KeyPathComponent, b: KeyPathComponent) -> Bool {
    switch (a, b) {
    case (.struct(offset: let a), .struct(offset: let b)),
         (.class (offset: let a), .class (offset: let b)):
      return a == b
    case (.optionalChain, .optionalChain),
         (.optionalForce, .optionalForce),
         (.optionalWrap, .optionalWrap):
      return true
    case (.get(id: let id1, accessors: _, argument: let argument1),
          .get(id: let id2, accessors: _, argument: let argument2)),

         (.mutatingGetSet(id: let id1, accessors: _, argument: let argument1),
          .mutatingGetSet(id: let id2, accessors: _, argument: let argument2)),

         (.nonmutatingGetSet(id: let id1, accessors: _, argument: let argument1),
          .nonmutatingGetSet(id: let id2, accessors: _, argument: let argument2)):
      if id1 != id2 {
        return false
      }
      if let arg1 = argument1, let arg2 = argument2 {
        return arg1.witnesses.equals(
          arg1.data.baseAddress!/*.unsafelyUnwrapped*/,
          arg2.data.baseAddress!/*.unsafelyUnwrapped*/,
          arg1.data.count - arg1.witnessSizeAdjustment)
      }
      // If only one component has arguments, that should indicate that the
      // only arguments in that component were generic captures and therefore
      // not affecting equality.
      return true
    case (.struct, _),
         (.class,  _),
         (.optionalChain, _),
         (.optionalForce, _),
         (.optionalWrap, _),
         (.get, _),
         (.mutatingGetSet, _),
         (.nonmutatingGetSet, _):
      return false
    }
  }

  @_effects(releasenone)
  internal func hash(into hasher: inout Hasher) {
    func appendHashFromArgument(
      _ argument: KeyPathComponent.ArgumentRef?
    ) {
      if let argument = argument {
        let hash = argument.witnesses.hash(
          argument.data.baseAddress!/*.unsafelyUnwrapped*/,
          argument.data.count - argument.witnessSizeAdjustment)
        // Returning 0 indicates that the arguments should not impact the
        // hash value of the overall key path.
        // FIXME(hasher): hash witness should just mutate hasher directly
        if hash != 0 {
          hasher.combine(hash)
        }
      }
    }
    switch self {
    case .struct(offset: let a):
      hasher.combine(0)
      hasher.combine(a)
    case .class(offset: let b):
      hasher.combine(1)
      hasher.combine(b)
    case .optionalChain:
      hasher.combine(2)
    case .optionalForce:
      hasher.combine(3)
    case .optionalWrap:
      hasher.combine(4)
    case .get(id: let id, accessors: _, argument: let argument):
      hasher.combine(5)
      hasher.combine(id)
      appendHashFromArgument(argument)
    case .mutatingGetSet(id: let id, accessors: _, argument: let argument):
      hasher.combine(6)
      hasher.combine(id)
      appendHashFromArgument(argument)
    case .nonmutatingGetSet(id: let id, accessors: _, argument: let argument):
      hasher.combine(7)
      hasher.combine(id)
      appendHashFromArgument(argument)
    }
  }
}

internal enum KeyPathComputedIDKind {
  case pointer
  case storedPropertyIndex
  case vtableOffset
}

internal enum KeyPathComputedIDResolution {
  case resolved
  case resolvedAbsolute
  case indirectPointer
  case functionCall
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
    
    internal var isStoredMutable: Bool {
      _internalInvariant(kind == .struct || kind == .class)
      return _value & Header.storedMutableFlag != 0
    }

    internal static var computedMutatingFlag: UInt32 {
      return _SwiftKeyPathComponentHeader_ComputedMutatingFlag
    }
    internal var isComputedMutating: Bool {
      _internalInvariant(kind == .computed)
      return _value & Header.computedMutatingFlag != 0
    }

    internal static var computedSettableFlag: UInt32 {
      return _SwiftKeyPathComponentHeader_ComputedSettableFlag
    }
    internal var isComputedSettable: Bool {
      _internalInvariant(kind == .computed)
      return _value & Header.computedSettableFlag != 0
    }
    
    internal static var computedHasArgumentsFlag: UInt32 {
      return _SwiftKeyPathComponentHeader_ComputedHasArgumentsFlag
    }
    internal var hasComputedArguments: Bool {
      _internalInvariant(kind == .computed)
      return _value & Header.computedHasArgumentsFlag != 0
    }
    
    // If a computed component is instantiated from an external property
    // descriptor, and both components carry arguments, we need to carry some
    // extra matter to be able to map between the client and external generic
    // contexts.
    internal static var computedInstantiatedFromExternalWithArgumentsFlag: UInt32 {
      return _SwiftKeyPathComponentHeader_ComputedInstantiatedFromExternalWithArgumentsFlag
    }
    internal var isComputedInstantiatedFromExternalWithArguments: Bool {
      get {
        _internalInvariant(kind == .computed)
        return
          _value & Header.computedInstantiatedFromExternalWithArgumentsFlag != 0
      }
      set {
        _internalInvariant(kind == .computed)
        _value =
            _value & ~Header.computedInstantiatedFromExternalWithArgumentsFlag
          | (newValue ? Header.computedInstantiatedFromExternalWithArgumentsFlag
                      : 0)
      }
    }
    internal static var externalWithArgumentsExtraSize: Int {
      return MemoryLayout<Int>.size
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
  
  internal var bodySize: Int {
    let ptrSize = MemoryLayout<Int>.size
    switch header.kind {
    case .struct, .class:
      if header.storedOffsetPayload == Header.outOfLineOffsetPayload {
        return 4 // overflowed
      }
      return 0
    case .external:
      _internalInvariantFailure("should be instantiated away")
    case .optionalChain, .optionalForce, .optionalWrap:
      return 0
    case .computed:
      // align to pointer, minimum two pointers for id and get
      var total = Header.pointerAlignmentSkew + ptrSize * 2
      // additional word for a setter
      if header.isComputedSettable {
        total += ptrSize
      }
      // include the argument size
      if header.hasComputedArguments {
        // two words for argument header: size, witnesses
        total += ptrSize * 2
        // size of argument area
        total += _computedArgumentSize
        if header.isComputedInstantiatedFromExternalWithArguments {
          total += Header.externalWithArgumentsExtraSize
        }
      }
      return total
    }
  }
  
  internal var _structOrClassOffset: Int {
    _internalInvariant(header.kind == .struct || header.kind == .class,
                 "no offset for this kind")
    // An offset too large to fit inline is represented by a signal and stored
    // in the body.
    if header.storedOffsetPayload == Header.outOfLineOffsetPayload {
      // Offset overflowed into body
      _internalInvariant(body.count >= MemoryLayout<UInt32>.size,
                   "component not big enough")
      return Int(body.load(as: UInt32.self))
    }
    return Int(header.storedOffsetPayload)
  }
  
  internal var _computedArgumentHeaderPointer: UnsafeRawPointer {
    _internalInvariant(header.hasComputedArguments, "no arguments")

    return body.baseAddress!/*.unsafelyUnwrapped*/
      + Header.pointerAlignmentSkew
      + MemoryLayout<Int>.size *
         (header.isComputedSettable ? 3 : 2)
  }
  
  internal var _computedArgumentSize: Int {
    return _computedArgumentHeaderPointer.load(as: Int.self)
  }
  
  internal var value: KeyPathComponent {
    switch header.kind {
    case .struct:
      return .struct(offset: _structOrClassOffset)
    case .class:
      return .class(offset: _structOrClassOffset)
    case .optionalChain:
      return .optionalChain
    case .optionalForce:
      return .optionalForce
    case .optionalWrap:
      return .optionalWrap
    case .computed:
      fatalError("Did not account for computed stuff yet.")
//      let isSettable = header.isComputedSettable
//      let isMutating = header.isComputedMutating
//
//      let id = _computedID
//      let accessors = _computedAccessors
//      // Argument value is unused if there are no arguments.
//      let argument: KeyPathComponent.ArgumentRef?
//      if header.hasComputedArguments {
//        argument = KeyPathComponent.ArgumentRef(
//          data: UnsafeRawBufferPointer(start: _computedArguments,
//                                       count: _computedArgumentSize),
//          witnesses: _computedArgumentWitnesses,
//          witnessSizeAdjustment: _computedArgumentWitnessSizeAdjustment)
//      } else {
//        argument = nil
//      }
//
//      switch (isSettable, isMutating) {
//      case (false, false):
//        return .get(id: id, accessors: accessors, argument: argument)
//      case (true, false):
//        return .nonmutatingGetSet(id: id,
//                                  accessors: accessors,
//                                  argument: argument)
//      case (true, true):
//        return .mutatingGetSet(id: id,
//                               accessors: accessors,
//                               argument: argument)
//      case (false, true):
//        _internalInvariantFailure("impossible")
//      }
    case .external:
      _internalInvariantFailure("should have been instantiated away")
    }
  }
  
  internal func destroy() {
      switch header.kind {
      case .struct,
           .class,
           .optionalChain,
           .optionalForce,
           .optionalWrap:
        print("RawKeyPathComponent branch 1")
        break
      case .computed:
        print("RawKeyPathComponent branch 2")
        fatalError("Not yet implemented")
//        // Run destructor, if any
//        if header.hasComputedArguments,
//           let destructor = _computedArgumentWitnesses.destroy {
//          destructor(_computedMutableArguments,
//                   _computedArgumentSize - _computedArgumentWitnessSizeAdjustment)
//        }
      case .external:
        print("RawKeyPathComponent branch 3")
        _internalInvariantFailure("should have been instantiated away")
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
      // properties. In the Swift stdlib, this case would execute other code.
      // That code is left out because it is not necessary for this use case.
      fatalError("Implement support for key paths to computed properties.")
      break
    case .external:
      _internalInvariantFailure("should have been instantiated away")
    }
    buffer = UnsafeMutableRawBufferPointer(
      start: buffer.baseAddress!/*.unsafelyUnwrapped*/ + componentSize,
      count: buffer.count - componentSize)
  }
}

internal func _pop<T>(from: inout UnsafeRawBufferPointer,
                      as type: T.Type) -> T {
  let buffer = _pop(from: &from, as: type, count: 1)
  return buffer.baseAddress!/*.unsafelyUnwrapped*/.pointee
}
internal func _pop<T>(from: inout UnsafeRawBufferPointer,
                      as: T.Type,
                      count: Int) -> UnsafeBufferPointer<T> {
  _internalInvariant(_isPOD(T.self), "should be POD")
  print("pointer1: \(from)")
  from = MemoryLayout<T>._roundingUpBaseToAlignment(from)
  print("pointer2: \(from)")
  let byteCount = MemoryLayout<T>.stride * count
  let result = UnsafeBufferPointer(
    start: from.baseAddress!/*.unsafelyUnwrapped*/.assumingMemoryBound(to: T.self),
    count: count)

  from = UnsafeRawBufferPointer(
    start: from.baseAddress!/*.unsafelyUnwrapped*/ + byteCount,
    count: from.count - byteCount)
  return result
}

internal struct KeyPathBuffer {
  internal var data: UnsafeRawBufferPointer
  internal var trivial: Bool
  internal var hasReferencePrefix: Bool

  internal init(base: UnsafeRawPointer) {
    let header = base.load(as: Header.self)
    data = UnsafeRawBufferPointer(
      start: base + MemoryLayout<Int>.size,
      count: header.size)
    trivial = header.trivial
    hasReferencePrefix = header.hasReferencePrefix
  }

  internal struct Builder {
    internal var buffer: UnsafeMutableRawBufferPointer
    internal init(_ buffer: UnsafeMutableRawBufferPointer) {
      self.buffer = buffer
    }
    internal mutating func pushRaw(
      size: Int, alignment: Int
    ) -> UnsafeMutableRawBufferPointer {
      var baseAddress = buffer.baseAddress!/*.unsafelyUnwrapped*/
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
    
    internal var size: Int { return Int(_value & Header.sizeMask) }
    internal var trivial: Bool { return _value & Header.trivialFlag != 0 }
    internal var hasReferencePrefix: Bool {
      get {
        return _value & Header.hasReferencePrefixFlag != 0
      }
      set {
        if newValue {
          _value |= Header.hasReferencePrefixFlag
        } else {
          _value &= ~Header.hasReferencePrefixFlag
        }
      }
    }
  }
  
  internal func destroy() {
    // Short-circuit if nothing in the object requires destruction.
    if trivial { print("was trivial"); return }

    var bufferToDestroy = self
    while true {
      print("destroying one component")
      let (component, type) = bufferToDestroy.next()
      component.destroy()
      guard let _ = type else { break }
    }
  }
  
  internal mutating func next() -> (RawKeyPathComponent, Any.Type?) {
    let header = _pop(from: &data, as: RawKeyPathComponent.Header.self)
    // Track if this is the last component of the reference prefix.
    if header.endOfReferencePrefix {
      _internalInvariant(self.hasReferencePrefix,
                   "beginMutation marker in non-reference-writable key path?")
      self.hasReferencePrefix = false
    }
    
    var component = RawKeyPathComponent(header: header, body: data)
    // Shrinkwrap the component buffer size.
    let size = component.bodySize
    component.body = UnsafeRawBufferPointer(start: component.body.baseAddress,
                                            count: size)
    _ = _pop(from: &data, as: Int8.self, count: size)

    // fetch type, which is in the buffer unless it's the final component
    let nextType: Any.Type?
    if data.isEmpty {
      nextType = nil
    } else {
      nextType = _pop(from: &data, as: Any.Type.self)
    }
    return (component, nextType)
  }
}

internal enum KeyPathStructOrClass {
  case `struct`, `class`
}
