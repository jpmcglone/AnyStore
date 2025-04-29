import SwiftUI
import Factory
import AnyStore

@propertyWrapper
@MainActor
public struct Stored<T: Identifiable>: DynamicProperty {
  private let id: T.ID
  private let store: AnyStore
  @State private var object: T

  public init(wrappedValue: T) {
    self.store = .shared
    self.id = wrappedValue.id
    _object = State(initialValue: store.fetchOrInsert(wrappedValue))
  }

  public init(_ store: AnyStore, wrappedValue: T) {
    self.store = store
    self.id = wrappedValue.id
    _object = State(initialValue: store.fetchOrInsert(wrappedValue))
  }

  public var wrappedValue: T {
    get { store.fetch(id) ?? object }
    nonmutating set {
      object = newValue
      store.save(newValue)
    }
  }

  public var projectedValue: Binding<T> {
    Binding(
      get: { wrappedValue },
      set: { newValue in
        object = newValue
        store.save(newValue)
      }
    )
  }
}
