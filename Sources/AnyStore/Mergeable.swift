import Foundation

/// Mergeable allows intelligent merging of objects based on updatedAt or custom logic.
public protocol Mergeable {
  var updatedAt: Date? { get }
  func merged(with new: Self) -> Self
}
