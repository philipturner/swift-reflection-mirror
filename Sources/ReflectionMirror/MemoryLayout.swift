//
//  MemoryLayout.swift
//  
//
//  Created by Philip Turner on 5/29/22.
//

extension MemoryLayout {
  internal static var _alignmentMask: Int { return alignment - 1 }
  
  internal static func _roundingUpBaseToAlignment(_ value: UnsafeRawBufferPointer) -> UnsafeRawBufferPointer {
    let baseAddressBits = Int(bitPattern: value.baseAddress)
    var misalignment = baseAddressBits & _alignmentMask
    if misalignment != 0 {
      print("It was misaligned. \(misalignment) - \(baseAddressBits)")
      misalignment = _alignmentMask & -misalignment
      return UnsafeRawBufferPointer(
        start: UnsafeRawPointer(bitPattern: baseAddressBits + misalignment),
        count: value.count - misalignment)
    }
    return value
  }
}
