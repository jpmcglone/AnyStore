import Combine
import SwiftUI

@MainActor
final class StoredBox<T: Identifiable>: ObservableObject where T.ID: CustomStringConvertible {
  @Published var object: T
  private var token: AnyCancellable?
  private let store: AnyStore
  private let id: T.ID

  init(wrappedValue: T, store: AnyStore = .shared) {
    self.object = store.fetchOrInsert(wrappedValue)
    self.id = wrappedValue.id
    self.store = store
    subscribe()
  }

  private func subscribe() {
    token = store.publisher(for: id)
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in
        guard let self else { return }
        if let latest: T = store.fetch(self.id) {
          // Default: always update if not Equatable
          self.object = latest
        }
      }
  }

  func save(_ newValue: T) {
    object = newValue
    store.save(newValue)
  }
}

extension StoredBox where T: Equatable {
  private func shouldUpdate(with latest: T) -> Bool {
    self.object != latest
  }

  // Override subscribe for Equatable types
  fileprivate func subscribe() {
    token = store.publisher(for: id)
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in
        guard let self else { return }
        if let latest: T = store.fetch(self.id), self.object != latest {
          self.object = latest
        }
      }
  }
}

@propertyWrapper
@MainActor
public struct Stored<T: Identifiable>: DynamicProperty where T.ID: CustomStringConvertible {
  @StateObject private var box: StoredBox<T>

  public init(wrappedValue: T) {
    _box = StateObject(wrappedValue: StoredBox(wrappedValue: wrappedValue))
  }

  public init(_ store: AnyStore, wrappedValue: T) {
    _box = StateObject(wrappedValue: StoredBox(wrappedValue: wrappedValue, store: store))
  }

  public var wrappedValue: T {
    get { box.object }
    nonmutating set { box.save(newValue) }
  }

  public var projectedValue: Binding<T> {
    Binding(
      get: { box.object },
      set: { box.save($0) }
    )
  }
}
