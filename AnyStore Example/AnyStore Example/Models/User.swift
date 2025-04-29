import AnyStore
import Foundation

struct User: Identifiable, Mergeable {
  let id: UUID
  var name: String
  var bio: String?
  var updatedAt: Date?

  func merged(with new: User) -> User {
    User(
      id: id,
      name: new.name.isEmpty ? self.name : new.name,
      bio: new.bio ?? self.bio,
      updatedAt: max(self.updatedAt ?? .distantPast, new.updatedAt ?? .distantPast)
    )
  }
}
