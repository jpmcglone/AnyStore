import Foundation

public enum FieldState<Value> {
  case absent
  case present(Value)
}

extension FieldState {
  public var value: Value? {
    switch self {
    case .absent:
      return nil
    case .present(let value):
      return value
    }
  }
}
