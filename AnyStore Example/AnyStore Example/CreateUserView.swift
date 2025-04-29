import AnyStore
import Factory
import SwiftUI

struct CreateUserView: View {
  @Environment(\.dismiss) var dismiss
  @InjectedObject(\.store) var store

  @State private var name: String = ""
  @State private var bio: String = ""

  var body: some View {
    VStack(spacing: 20) {
      TextField("Name", text: $name)
        .textFieldStyle(.roundedBorder)

      TextField("Bio", text: $bio)
        .textFieldStyle(.roundedBorder)

      Button("Save User") {
        let user = User(
          id: UUID(),
          name: name,
          bio: bio.isEmpty ? nil : bio,
          updatedAt: Date()
        )
        store.save(user)
        dismiss()
      }
      .buttonStyle(.borderedProminent)
    }
    .padding()
    .navigationTitle("Create User")
  }
}
