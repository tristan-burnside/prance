# Prance
A language and LLVM based compiler for teaching/learning about [Protocol Oriented Programming](https://developer.apple.com/videos/play/wwdc2015/408/) concepts.

Prance code uses an Object-oriented style without type inheritence. This is intended to prompt users into finding non heirarchical solutions to problems.

**v0.1**

Support for:
- if-else
- c-like for statements
- while loops
- primitive double, float, int and string types
- stand alone functions
- reference types
  - properties
  - methods
  - protocol conformance
- protocols
  - functions
  - default implementations
- arithmetic operators
- logical comparators

## Learn more
To learn more about the language please read the [language guide](./Docs/intro.md).

## Getting started
get llvm `brew install llvm@21`

clone this repo 

run `swift ./utils/make-pkgconfig.swift`

install pkgconfig `brew install pkgconfig`

open `Package.swift`

build in XCode

compiled `Prance` binary should reside in ./DerivedData/Prance/Build/Products/Debug/Prance

compile the demo code at `samples/demo.prance` by calling `<Path to prance>/Prance ./samples/demo.prance` or using the run action on the Prance scheme.

run the demo code `./samples/demo`
