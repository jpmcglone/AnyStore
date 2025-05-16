import Foundation
import Combine
import SwiftUI

@MainActor
public final class AnyStore: ObservableObject {
  public static let shared = AnyStore()

  private var storage: [String: Any] = [:]
  private var typeIndex: [ObjectIdentifier: [String: Any]] = [:]

  private let queue = DispatchQueue(label: "com.anystore.queue", attributes: .concurrent)
  private var subjects: [String: PassthroughSubject<Void, Never>] = [:]

  private func subject(for key: String) -> PassthroughSubject<Void, Never> {
    if let s = subjects[key] { return s }
    let s = PassthroughSubject<Void, Never>()
    subjects[key] = s
    return s
  }

  public init() {}

  public func delete<T: Identifiable>(_ object: T) {
    let key = makeKey(for: object.id)
    let typeKey = ObjectIdentifier(T.self)

    queue.sync(flags: .barrier) {
      DispatchQueue.main.async {
        self.storage.removeValue(forKey: key)
        self.typeIndex[typeKey]?[key] = nil
        print("🗑️ [AnyStore] Deleted <\(String(describing: T.self))> for key \(key)")
      }
    }
  }

  // MARK: - Save for Mergeable types
  @discardableResult
  public func save<T: Identifiable & Mergeable>(_ object: T) -> T {
    let key = makeKey(for: object.id)
    let typeKey = ObjectIdentifier(T.self)
    var result = object

    queue.sync(flags: .barrier) {
      if let existing = storage[key] as? T {
        if let existingDate = existing.updatedAt,
           let newDate = object.updatedAt,
           existingDate > newDate {
          print("🟡 [AnyStore] Skipped outdated update for <\(String(describing: T.self))> key \(key)")
          result = existing
        } else {
          result = existing.merged(with: object)
        }
      }

      let value = result
      DispatchQueue.main.async {
        self.storage[key] = value
        self.typeIndex[typeKey, default: [:]][key] = value
        print("🟢 [AnyStore] Saved <\(String(describing: T.self))> for key \(key)")
      }
    }

    return result
  }

  public func clear() {
    queue.sync(flags: .barrier) {
      DispatchQueue.main.async {
        self.storage.removeAll()
        self.typeIndex.removeAll()
        print("🧹 [AnyStore] Store cleared")
      }
    }
  }

  // MARK: - Save for plain Identifiable types
  @discardableResult
  public func save<T: Identifiable>(_ object: T) -> T {
    let key = makeKey(for: object.id)
    let typeKey = ObjectIdentifier(T.self)

    queue.sync(flags: .barrier) {
      self.storage[key] = object
      self.typeIndex[typeKey, default: [:]][key] = object
      print("🟢 [AnyStore] Overwrote <\(String(describing: T.self))> for key \(key)")
    }

    subject(for: key).send()
    return object
  }

  @discardableResult
  public func save<T: Identifiable & Equatable>(_ object: T) -> T {
    let key = makeKey(for: object.id)
    let typeKey = ObjectIdentifier(T.self)
    var shouldSend = true

    queue.sync(flags: .barrier) {
      if let existing = storage[key] as? T, existing == object {
        shouldSend = false // Value hasn't changed, skip notification
      }
      self.storage[key] = object
      self.typeIndex[typeKey, default: [:]][key] = object
      print("🟢 [AnyStore] Overwrote <\(String(describing: T.self))> for key \(key)")
    }

    if shouldSend {
      subject(for: key).send()
    }
    return object
  }

  public func publisher<ID: CustomStringConvertible>(for id: ID) -> AnyPublisher<Void, Never> {
    let key = makeKey(for: id)
    return subject(for: key).eraseToAnyPublisher()
  }

  // MARK: - Fetch
  public func fetch<T: Identifiable>(_ id: T.ID) -> T? {
    let key = makeKey(for: id)
    var result: T?
    queue.sync {
      result = storage[key] as? T
    }
    print(result != nil
          ? "🔍 [AnyStore] Fetched <\(String(describing: T.self))> for key \(key)"
          : "🟥 [AnyStore] Failed to fetch <\(String(describing: T.self))> for key \(key)")
    return result
  }

  // MARK: - Fetch or Insert
  @discardableResult
  public func fetchOrInsert<T: Identifiable>(_ object: T) -> T {
    if let existing: T = fetch(object.id) {
      return existing
    } else {
      return save(object)
    }
  }

  // MARK: - Fetch All (O(1))
  public func all<T: Identifiable>(of type: T.Type = T.self) -> [T] {
    let typeKey = ObjectIdentifier(T.self)
    var results: [T] = []
    queue.sync {
      if let map = typeIndex[typeKey] {
        results = map.values.compactMap { $0 as? T }
      }
    }
    print("📋 [AnyStore] Returning all <\(String(describing: T.self))>s (\(results.count) total)")
    return results
  }

  // MARK: - Helpers
  private func makeKey<ID>(for id: ID) -> String {
    "\(id)"
  }
}
