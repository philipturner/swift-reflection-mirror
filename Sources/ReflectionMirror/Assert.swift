//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

/// Internal checks.
///
/// Internal checks are to be used for checking correctness conditions in the
/// standard library. They are only enable when the standard library is built
/// with the build configuration INTERNAL_CHECKS_ENABLED enabled. Otherwise, the
/// call to this function is a noop.
@usableFromInline @_transparent
internal func _internalInvariant(
  _ condition: @autoclosure () -> Bool, _ message: String = "",
  file: StaticString = #file, line: UInt = #line
) {
#if INTERNAL_CHECKS_ENABLED
  if !_fastPath(condition()) {
    fatalError(message, file: file, line: line)
  }
#endif
}

@usableFromInline @_transparent
internal func _internalInvariantFailure(
  _ message: String = "",
  file: StaticString = #file, line: UInt = #line
) -> Never {
  _internalInvariant(false, message, file: file, line: line)
  Builtin.conditionallyUnreachable()
}
