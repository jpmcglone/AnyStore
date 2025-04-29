import AnyStore
import Factory
import SwiftUI

struct ContentView: View {
  @InjectedObject(\.store) var store
  private var users: [User] {
    store.all(of: User.self)
  }

  var body: some View {
    NavigationView {
      List {
        Section(header: Text("Users")) {
          ForEach(users) { user in
            NavigationLink(destination: UpdateUserView(user: user)) {
              userRow(for: user)
            }
          }
        }

        Section {
          NavigationLink("Create User", destination: CreateUserView())
        }
      }
      .navigationTitle("AnyStore Demo")
    }
  }

  func userRow(for user: User) -> some View {
    VStack(alignment: .leading) {
      Text(user.name)
        .font(.headline)
      if let bio = user.bio {
        Text(bio)
          .font(.subheadline)
          .foregroundColor(.secondary)
      }
    }
  }
}
