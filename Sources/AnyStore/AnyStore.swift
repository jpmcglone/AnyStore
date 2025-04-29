import Foundation
import Combine
import SwiftUI

public final class AnyStore: ObservableObject {
  public static let shared = AnyStore()

  @Published private var storage: [String: Any] = [:]
  private var typeIndex: [ObjectIdentifier: [String: Any]] = [:]

  private let queue = DispatchQueue(label: "com.anystore.queue", attributes: .concurrent)

  public init() {}

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
          print("🟡 [AnyStore] Skipped outdated update for \(key)")
          result = existing
        } else {
          result = existing.merged(with: object)
        }
      }

      let value = result
      DispatchQueue.main.async {
        self.storage[key] = value
        self.typeIndex[typeKey, default: [:]][key] = value
        print("🟢 [AnyStore] Saved object for key \(key) (\(T.self))")
      }
    }

    return result
  }

  // MARK: - Save for plain Identifiable types
  @discardableResult
  public func save<T: Identifiable>(_ object: T) -> T {
    let key = makeKey(for: object.id)
    let typeKey = ObjectIdentifier(T.self)

    queue.sync(flags: .barrier) {
      let value = object
      DispatchQueue.main.async {
        self.storage[key] = value
        self.typeIndex[typeKey, default: [:]][key] = value
        print("🟢 [AnyStore] Overwrote object for key \(key) (\(T.self))")
      }
    }

    return object
  }

  // MARK: - Fetch
  public func fetch<T: Identifiable>(_ id: T.ID) -> T? {
    let key = makeKey(for: id)
    var result: T?
    queue.sync {
      result = storage[key] as? T
    }
    print(result != nil
          ? "🔍 [AnyStore] Fetched object for key \(key)"
          : "🟥 [AnyStore] Failed to fetch object for key \(key)")
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
    print("📋 [AnyStore] Returning all \(T.self)s (\(results.count) total)")
    return results
  }

  // MARK: - Helpers
  private func makeKey<ID>(for id: ID) -> String {
    "\(id)"
  }
}
