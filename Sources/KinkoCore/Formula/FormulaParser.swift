import Foundation

/// 演算子の優先順位は Excel と同じ（低い順に）：比較、&、+ -、* /、^、%、符号の -。
/// Excel では符号の - が ^ より先に結びつくので、-2^2 は 4 になる
struct FormulaParser {
  let tokens: [FormulaToken]
  private var index = 0

  init(tokens: [FormulaToken]) {
    self.tokens = tokens
  }

  mutating func parse() throws(FormulaSyntaxError) -> FormulaExpr {
    let expr = try comparison()
    guard index == tokens.count else { throw FormulaSyntaxError() }
    return expr
  }

  private var current: FormulaToken.Kind? { index < tokens.count ? tokens[index].kind : nil }

  private mutating func takeOperator(_ candidates: Set<String>) -> String? {
    if case .op(let op) = current, candidates.contains(op) {
      index += 1
      return op
    }
    return nil
  }

  private mutating func comparison() throws(FormulaSyntaxError) -> FormulaExpr {
    var expr = try concatenation()
    while let op = takeOperator(["=", "<>", "<", ">", "<=", ">="]) {
      expr = .binary(op, expr, try concatenation())
    }
    return expr
  }

  private mutating func concatenation() throws(FormulaSyntaxError) -> FormulaExpr {
    var expr = try additive()
    while let op = takeOperator(["&"]) {
      expr = .binary(op, expr, try additive())
    }
    return expr
  }

  private mutating func additive() throws(FormulaSyntaxError) -> FormulaExpr {
    var expr = try multiplicative()
    while let op = takeOperator(["+", "-"]) {
      expr = .binary(op, expr, try multiplicative())
    }
    return expr
  }

  private mutating func multiplicative() throws(FormulaSyntaxError) -> FormulaExpr {
    var expr = try power()
    while let op = takeOperator(["*", "/"]) {
      expr = .binary(op, expr, try power())
    }
    return expr
  }

  private mutating func power() throws(FormulaSyntaxError) -> FormulaExpr {
    var expr = try percent()
    while let op = takeOperator(["^"]) {
      expr = .binary(op, expr, try percent())
    }
    return expr
  }

  private mutating func percent() throws(FormulaSyntaxError) -> FormulaExpr {
    var expr = try unary()
    while takeOperator(["%"]) != nil {
      expr = .percent(expr)
    }
    return expr
  }

  private mutating func unary() throws(FormulaSyntaxError) -> FormulaExpr {
    if let op = takeOperator(["-", "+"]) {
      return .unary(op, try unary())
    }
    return try primary()
  }

  private mutating func primary() throws(FormulaSyntaxError) -> FormulaExpr {
    guard let token = current else { throw FormulaSyntaxError() }
    index += 1
    switch token {
    case .number(let number): return .literal(.number(number))
    case .string(let text): return .literal(.text(text))
    case .bool(let bool): return .literal(.bool(bool))
    case .error(let error): return .literal(.error(error))
    case .reference(let reference): return .reference(reference)
    case .name: return .literal(.error(.name))
    case .openParen:
      let expr = try comparison()
      guard current == .closeParen else { throw FormulaSyntaxError() }
      index += 1
      return expr
    case .function(let name):
      guard current == .openParen else { throw FormulaSyntaxError() }
      index += 1
      var arguments: [FormulaExpr] = []
      if current == .closeParen {
        index += 1
        return .call(name, arguments)
      }
      while true {
        if current == .comma || current == .closeParen {
          arguments.append(.missing)
        } else {
          arguments.append(try comparison())
        }
        if current == .comma {
          index += 1
          continue
        }
        guard current == .closeParen else { throw FormulaSyntaxError() }
        index += 1
        return .call(name, arguments)
      }
    default:
      throw FormulaSyntaxError()
    }
  }
}
