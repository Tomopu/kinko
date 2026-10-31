import Foundation

/// パスワードを続けて間違えた回数を、金庫ごとに数える。決めた回数に達したら金庫のファイルを消す設定のため。
///
/// 数えるのは、この Mac の Kinko で開こうとしたときだけ。ファイルをコピーして別の道具で試されると防げないので、
/// 手元の Mac で当て推量されることへの備えにすぎない（総当たりへの備えは、長いパスワードと Argon2id の重さ）
public struct UnlockAttempts: Codable, Equatable, Sendable {
  /// 設定で選べる回数。少なすぎると打ち間違いで消えてしまうので 5 回から
  public static let limits = [5, 10, 20]

  private var failures: [String: Int] = [:]

  public init() {}

  public enum Outcome: Equatable, Sendable {
    /// まだ消さない。remaining は、あと何回間違えると消すか（消さない設定なら nil）
    case retry(remaining: Int?)
    /// 決めた回数に達したので消す
    case erase
  }

  /// 続けて間違えた回数
  public func failures(of vault: String) -> Int { failures[vault] ?? 0 }

  /// あと何回間違えると消すか。消さない設定（limit が nil）なら nil。
  /// 回数を後から減らして、すでに超えているときは 1（次に間違えると消す）
  public func remaining(of vault: String, limit: Int?) -> Int? {
    limit.map { max($0 - failures(of: vault), 1) }
  }

  /// 間違えた回数を 1 つ増やし、消すかどうかを返す。消すときは数え直しのため記録も消す
  public mutating func recordFailure(of vault: String, limit: Int?) -> Outcome {
    let count = failures(of: vault) + 1
    if let limit, count >= limit {
      failures[vault] = nil
      return .erase
    }
    failures[vault] = count
    return .retry(remaining: remaining(of: vault, limit: limit))
  }

  /// 開けたら数え直す
  public mutating func recordSuccess(of vault: String) {
    failures[vault] = nil
  }
}
