# ReflectionMirror - Swift Stdlib copypasta

Swift's powerful runtime reflection mechanism is gated under a 
[System Programming Interface](https://github.com/apple/swift/blob/main/docs/ReferenceGuides/UnderscoredAttributes.md#_spispiname).
To access it, you must add `@_spi(Reflection)` before a statement that imports
the Swift Standard Library. This programming interface is removed from release 
toolchains, leaving developers with no choice but to use development toolchains
for [certain projects](https://github.com/s4tf). Until now.

This package serves a purpose similar to 
[philipturner/differentiation](https://github.com/philipturner/differentiation), 
in that it exposes a private API to the developer on release toolchains. Do not 
expect Apple to let any Xcode project depending on this package onto the iOS App 
Store. The purpose of bringing this feature to release toolchains isn't to build 
iOS apps, but to make it more accessible in situations where a development 
toolchain cannot be used. For example, iPad Swift Playgrounds.

## How to use

This package <s>copies</s> reimplements the contents of 
[ReflectionMirror.swift](https://github.com/apple/swift/blob/main/stdlib/public/core/ReflectionMirror.swift)
in the Swift Standard Library. It even gates the API-public functions under an
SPI, although this one can be used on release toolchains. To use this library,
replace all instances of the following:

```swift
@_spi(Reflection) import Swift
```

With an import of `ReflectionMirror`. This Swift module re-exports the Swift
Standard Library, so you do not need a second import statement for 
`import Swift`. 

```swift
@_spi(Reflection) import ReflectionMirror
```

You cannot SPI-import both `Swift` and `ReflectionMirror` at the same time on development 
toolchains, because that will cause a name collision with the following two functions. 
That is not an issue, because [ReflectionMirror.swift](https://github.com/apple/swift/blob/main/stdlib/public/core/ReflectionMirror.swift) 
contains the entire Reflection SPI of the Swift Standard Library (at least for 
now). This package also contains all of the SPI symbols because it reimplements 
that file. In other words, follow the instructions above and you'll be fine.

```swift
func _forEachField(
  of type: Any.Type,
  options: _EachFieldOptions = [],
  body: (UnsafePointer<CChar>, Int, Any.Type, _MetadataKind) -> Bool
) -> Bool

func _forEachFieldWithKeyPath<Root>(
  of type: Root.Type,
  options: _EachFieldOptions = [],
  body: (UnsafePointer<CChar>, PartialKeyPath<Root>) -> Bool
) -> Bool
```

## "Reimplemented" files of the Swift Stdlib

- [stdlib/public/core/Assert.swift](https://github.com/apple/swift/blob/main/stdlib/public/core/Assert.swift) (partially)
- [stdlib/public/core/KeyPath.swift](https://github.com/apple/swift/blob/main/stdlib/public/core/KeyPath.swift) (partially)
- [stdlib/public/core/ReflectionMirror.swift](https://github.com/apple/swift/blob/main/stdlib/public/core/ReflectionMirror.swift)
- [test/stdlib/ForEachField.swift](https://github.com/apple/swift/blob/main/test/stdlib/ForEachField.swift)
