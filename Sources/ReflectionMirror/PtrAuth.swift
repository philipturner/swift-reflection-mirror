//
//  PtrAuth.swift
//  
//
//  Created by Philip Turner on 5/29/22.
//

// Helpers for working with authenticated function pointers.
extension UnsafeRawPointer {
  /// Load a function pointer from memory that has been authenticated
  /// specifically for its given address.
  @_transparent
  internal func _loadAddressDiscriminatedFunctionPointer<T>(
    fromByteOffset offset: Int = 0,
    as type: T.Type,
    discriminator: UInt64
  ) -> T {
    fatalError("Have not yet implemented _PtrAuth")
//    let src = self + offset
//
//    let srcDiscriminator = _PtrAuth.blend(pointer: src,
//                                          discriminator: discriminator)
//    let ptr = src.load(as: UnsafeRawPointer.self)
//    let resigned = _PtrAuth.authenticateAndResign(
//      pointer: ptr,
//      oldKey: .processIndependentCode,
//      oldDiscriminator: srcDiscriminator,
//      newKey: .processIndependentCode,
//      newDiscriminator: _PtrAuth.discriminator(for: type))
//
//    return unsafeBitCast(resigned, to: type)
  }

  @_transparent
  internal func _loadAddressDiscriminatedFunctionPointer<T>(
    fromByteOffset offset: Int = 0,
    as type: Optional<T>.Type,
    discriminator: UInt64
  ) -> Optional<T> {
    fatalError("Have not yet implemented _PtrAuth")
//    let src = self + offset
//
//    let srcDiscriminator = _PtrAuth.blend(pointer: src,
//                                          discriminator: discriminator)
//    guard let ptr = src.load(as: Optional<UnsafeRawPointer>.self) else {
//      return nil
//    }
//    let resigned = _PtrAuth.authenticateAndResign(
//      pointer: ptr,
//      oldKey: .processIndependentCode,
//      oldDiscriminator: srcDiscriminator,
//      newKey: .processIndependentCode,
//      newDiscriminator: _PtrAuth.discriminator(for: T.self))
//
//    return .some(unsafeBitCast(resigned, to: T.self))
  }

}
