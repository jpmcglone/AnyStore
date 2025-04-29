import AnyStore
import Factory
import SwiftUI

struct ShowUserView: View {
  @Environment(\.dismiss) var dismiss

  @Stored var user: User
  
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Name: \(user.name)")
      Text("Bio: \(user.bio ?? "No Bio")")
      Text("Updated At: \(user.updatedAt?.formatted() ?? "Unknown")")
    }
    .padding()
    .navigationTitle("User Details")
  }
}
