import Foundation

func debugPrint(_ items: Any...) {
    let output = items.map { "\($0)" }.joined(separator: " ")
    fputs(output + "\n", stderr)
    fflush(stderr)
}
