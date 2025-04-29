import AnyStore
import Factory
import SwiftUI

struct UpdateUserView: View {
  @Environment(\.dismiss) var dismiss

  @InjectedObject(\.store) var store
  @Stored var user: User

  @State private var newName = ""
  @State private var newBio = ""

  var body: some View {
    VStack(spacing: 20) {
      Text("Editing: \(user.id.uuidString)")
        .font(.caption)
        .foregroundColor(.gray)

      TextField("New Name", text: $newName)
        .textFieldStyle(.roundedBorder)

      TextField("New Bio", text: $newBio)
        .textFieldStyle(.roundedBorder)

      Button("Save Changes") {
        var updated = user
        updated.name = newName
        updated.bio = newBio.isEmpty ? nil : newBio
        updated.updatedAt = Date()

        user = updated // <- ✅ Triggers auto-save
        dismiss()
      }
      .buttonStyle(.borderedProminent)
    }
    .padding()
    .navigationTitle("Update User")
    .task {
      newBio = user.bio ?? ""
      newName = user.name
    }
  }
}
