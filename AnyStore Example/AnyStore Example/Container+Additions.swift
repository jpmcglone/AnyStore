import AnyStore
import Factory

extension Container {
  var store: Factory<AnyStore> {
    Factory(self) {
      AnyStore.shared
    }
    .singleton
  }
}
