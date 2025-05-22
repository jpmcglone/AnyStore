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

  public func clear() {
    queue.sync(flags: .barrier) {
      DispatchQueue.main.async {
        self.storage.removeAll()
        self.typeIndex.removeAll()
        print("🧹 [AnyStore] Store cleared")
      }
    }
  }

  @discardableResult
  public func save<T: Identifiable>(_ object: T) -> T {
    let key = makeKey(for: object.id)
    let typeKey = ObjectIdentifier(T.self)
    var result: T = object
    var shouldSend = true

    queue.sync(flags: .barrier) {
      // Check if the existing object is the *same* concrete type as T. If not, replace it.
      if let existing = storage[key], !(existing is T) {
        self.storage.removeValue(forKey: key)
        self.typeIndex[typeKey]?[key] = nil
        print("⚠️ [AnyStore] Type mismatch for key \(key): replacing \(type(of: existing)) with \(type(of: object))")
      }

      // --- MERGEABLE HANDLING (if existing object IS T) ---
      if let mergeableNew = object as? any Mergeable,
         let existing = storage[key] as? T,
         let mergeableOld = existing as? any Mergeable,
         type(of: mergeableNew) == type(of: mergeableOld)
      {
        if let merged = mergeableOld.mergedAny(with: mergeableNew) as? T {
          result = merged
        }
      }
      // --- EQUATABLE HANDLING ---
      else if let equatableObject = object as? any Equatable,
              let existing = storage[key] as? T,
              let existingEquatable = existing as? any Equatable,
              type(of: equatableObject) == type(of: existingEquatable),
              equatableObject.isEqualTo(existingEquatable)
      {
        result = existing
        shouldSend = false
      }
      // --- DEFAULT OVERWRITE ---
      self.storage[key] = result
      self.typeIndex[typeKey, default: [:]][key] = result
      print("🟢 [AnyStore] Saved <\(String(describing: T.self))> for key \(key)")
    }

    if shouldSend {
      subject(for: key).send()
    }
    return result
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

protocol _MergeableBox {
  func mergedAny(with other: Any) -> Any?
}

extension Mergeable {
  func mergedAny(with other: Any) -> Any? {
    guard let otherSelf = other as? Self else { return nil }
    return self.merged(with: otherSelf)
  }
}

extension Mergeable where Self: AnyObject {
  func asMergeableBox() -> _MergeableBox {
    return _MergeableBoxImpl(self)
  }
}

private class _MergeableBoxImpl<T: Mergeable>: _MergeableBox {
  let base: T
  init(_ base: T) { self.base = base }
  func mergedAny(with other: Any) -> Any? {
    guard let otherT = other as? T else { return nil }
    return base.merged(with: otherT)
  }
}

extension Equatable {
  func isEqualTo(_ other: Any) -> Bool {
    guard let otherTyped = other as? Self else { return false }
    return self == otherTyped
  }
}
