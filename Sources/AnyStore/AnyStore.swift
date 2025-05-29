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

  private var subjectAccessTimes: [String: Date] = [:]
  private let subjectCleanupInterval: TimeInterval = 300 // 5 minutes

  public var maxItems: Int = 10_000
  private var accessOrder: [String] = []

  // MARK: - Logging

  public enum LogLevel {
    case none, errors, operations, verbose
  }

  public var logLevel: LogLevel = .operations

  private func subject(for key: String) -> PassthroughSubject<Void, Never> {
    subjectAccessTimes[key] = Date()

    if let s = subjects[key] {
      return s
    }

    let s = PassthroughSubject<Void, Never>()
    subjects[key] = s

    // Periodic cleanup (every 100 subject accesses)
    if subjects.count % 100 == 0 {
      cleanupUnusedSubjects()
    }

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

  // MARK: - Bulk Delete

  public func delete<T: Identifiable>(_ objects: [T]) {
    guard !objects.isEmpty else { return }

    let typeKey = ObjectIdentifier(T.self)

    queue.sync(flags: .barrier) {
      DispatchQueue.main.async {
        for object in objects {
          let key = self.makeKey(for: object.id)
          self.storage.removeValue(forKey: key)
          self.typeIndex[typeKey]?[key] = nil
        }
        print("🗑️📦 [AnyStore] Bulk deleted \(objects.count) <\(String(describing: T.self))> objects")
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
        if logLevel == .operations || logLevel == .verbose {
          print("⚠️ [AnyStore] Type mismatch for key \(key): replacing \(type(of: existing)) with \(type(of: object))")
        }
      }

      // --- MERGEABLE HANDLING (if existing object IS T) ---
      if
        let mergeableNew = object as? any Mergeable,
        let existing = storage[key] as? T,
        let mergeableOld = existing as? any Mergeable,
        type(of: mergeableNew) == type(of: mergeableOld)
      {
        if let merged = mergeableOld.mergedAny(with: mergeableNew) as? T {
          result = merged
        }
      }
      // --- EQUATABLE HANDLING ---
      else if
        let equatableObject = object as? any Equatable,
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

      if logLevel == .operations || logLevel == .verbose {
        print("🟢 [AnyStore] Saved <\(String(describing: T.self))> for key \(key)")
      }
    }

    if shouldSend {
      subject(for: key).send()
    }
    return result
  }

  // MARK: - Bulk Save

  @discardableResult
  public func save<T: Identifiable>(_ objects: [T]) -> [T] {
    guard !objects.isEmpty else { return [] }

    let typeKey = ObjectIdentifier(T.self)
    var results: [T] = []
    var keysToNotify: [String] = []

    // Single barrier operation for all objects
    queue.sync(flags: .barrier) {
      for object in objects {
        let key = makeKey(for: object.id)
        var result: T = object
        var shouldSend = true

        // Check if the existing object is the *same* concrete type as T. If not, replace it.
        if let existing = storage[key], !(existing is T) {
          self.storage.removeValue(forKey: key)
          self.typeIndex[typeKey]?[key] = nil
          print("⚠️ [AnyStore] Type mismatch for key \(key): replacing \(type(of: existing)) with \(type(of: object))")
        }

        // --- MERGEABLE HANDLING (if existing object IS T) ---
        if
          let mergeableNew = object as? any Mergeable,
          let existing = storage[key] as? T,
          let mergeableOld = existing as? any Mergeable,
          type(of: mergeableNew) == type(of: mergeableOld)
        {
          if let merged = mergeableOld.mergedAny(with: mergeableNew) as? T {
            result = merged
          }
        }
        // --- EQUATABLE HANDLING ---
        else if
          let equatableObject = object as? any Equatable,
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

        results.append(result)
        if shouldSend {
          keysToNotify.append(key)
        }
      }

      // Single log entry for bulk operation
      print("📦 [AnyStore] Bulk saved \(results.count) <\(String(describing: T.self))> objects")
    }

    // Send notifications for all changed objects
    for key in keysToNotify {
      subject(for: key).send()
    }

    return results
  }

  public func publisher(for id: some CustomStringConvertible) -> AnyPublisher<Void, Never> {
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

    // Only log on errors or verbose mode
    if logLevel == .verbose || (logLevel == .errors && result == nil) {
      print(result != nil
        ? "🔍 [AnyStore] Fetched <\(String(describing: T.self))> for key \(key)"
        : "🟥 [AnyStore] Failed to fetch <\(String(describing: T.self))> for key \(key)")
    }
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
    if logLevel == .operations || logLevel == .verbose {
      print("📋 [AnyStore] Returning all <\(String(describing: T.self))>s (\(results.count) total)")
    }
    return results
  }

  // MARK: - Batch Fetch

  public func fetch<T: Identifiable>(_ ids: [T.ID]) -> [T] {
    var results: [T] = []
    queue.sync {
      results = ids.compactMap { storage[makeKey(for: $0)] as? T }
    }
    if logLevel == .operations || logLevel == .verbose {
      print("📋 [AnyStore] Batch fetched \(results.count)/\(ids.count) <\(String(describing: T.self))> objects")
    }
    return results
  }

  // MARK: - Helpers

  private func makeKey(for id: some Any) -> String {
    "\(id)"
  }

  // MARK: - Subject Cleanup

  private func cleanupUnusedSubjects() {
    let now = Date()
    let keysToRemove = subjectAccessTimes.compactMap { key, lastAccess in
      now.timeIntervalSince(lastAccess) > subjectCleanupInterval ? key : nil
    }

    for key in keysToRemove {
      subjects.removeValue(forKey: key)
      subjectAccessTimes.removeValue(forKey: key)
    }

    if logLevel == .verbose, !keysToRemove.isEmpty {
      print("🧹 [AnyStore] Cleaned up \(keysToRemove.count) unused subjects")
    }
  }

  // Save only if object changed
  @discardableResult
  public func saveIfChanged<T: Identifiable & Equatable>(_ object: T) -> (saved: Bool, result: T) {
    if let existing: T = fetch(object.id), existing == object {
      return (false, existing)
    }
    return (true, save(object))
  }

  // Upsert operation
  @discardableResult
  public func upsert<T: Identifiable>(_ object: T) -> (wasInsert: Bool, result: T) {
    let existing: T? = fetch(object.id)
    let wasInsert = existing == nil
    return (wasInsert, save(object))
  }

  // Filter with predicate
  public func filter<T: Identifiable>(_ type: T.Type, where predicate: (T) -> Bool) -> [T] {
    return all(of: type).filter(predicate)
  }

  // Find first matching
  public func first<T: Identifiable>(_ type: T.Type, where predicate: (T) -> Bool) -> T? {
    let typeKey = ObjectIdentifier(T.self)
    return queue.sync {
      guard let map = typeIndex[typeKey] else { return nil }
      return map.values.lazy.compactMap { $0 as? T }.first(where: predicate)
    }
  }

  // MARK: - Memory Management

  private func evictIfNeeded() {
    guard storage.count > maxItems else { return }

    let itemsToRemove = storage.count - maxItems + 100 // Remove extra 100
    let keysToRemove = Array(accessOrder.prefix(itemsToRemove))

    for key in keysToRemove {
      storage.removeValue(forKey: key)
      // Update type indices - remove from all type indices
      for (_, var typeMap) in typeIndex {
        typeMap.removeValue(forKey: key)
      }
    }
    accessOrder.removeFirst(itemsToRemove)
  }

  // MARK: - Metrics

  public var metrics: AnyStoreMetrics {
    let itemsByType = typeIndex.mapValues { $0.count }
    let itemsByTypeString = itemsByType.reduce(into: [String: Int]()) { result, pair in
      result[String(describing: pair.key)] = pair.value
    }

    return AnyStoreMetrics(
      totalItems: storage.count,
      itemsByType: itemsByTypeString,
      memoryUsage: MemoryLayout.size(ofValue: storage) + storage.count * 64, // Rough estimate
      hitRate: 1.0 // Placeholder - would need hit/miss tracking
    )
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

public struct AnyStoreMetrics {
  var totalItems: Int
  var itemsByType: [String: Int]
  var memoryUsage: Int
  var hitRate: Double
}
