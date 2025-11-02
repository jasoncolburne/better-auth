import Foundation

/// Simple error enum for the example app
enum ExampleError: Error {
    case invalidData
    case keypairNotGenerated
    case callInitializeFirst
    case callNextFirst
}
