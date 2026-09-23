// 词法分析：把 MoonBit 源码切成 token 流。
//
// 只需支撑“找到顶层类型定义”这一件事，因此：
// - 字符串字面量、普通注释、原始字符串行整体跳过（避免其中的 `{` `}` 干扰括号计数）；
// - 未知字符统一落成 `Other`，不报错（容错优于精确，符合“跳过而非解析”的策略）。

///|
/// 标识符起始字符：ASCII 字母、下划线，以及所有非 ASCII 码元
/// （后者覆盖中文标识符与 `@` 之后的包名首字符场景）。
fn is_ident_start(c : UInt16) -> Bool {
  (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95 || c >= 128
}

///|
/// 标识符后续字符。`.` 计入标识符，便于把 `@json.Json` 之类整体吞掉，
/// 减少 token 数量（类型原文仍以源码切片为准，不依赖这里）。
fn is_ident_continue(c : UInt16) -> Bool {
  is_ident_start(c) || (c >= 48 && c <= 57) || c == 46
}

///|
/// 剥离 doc comment 的 `///` 前缀，并处理 `///|` 块分隔符。
/// 返回值已去除首尾空白；`///|` 这类纯分隔行会得到空串。
fn normalize_doc_line(raw : String) -> String {
  let mut t = raw.trim_start().to_owned()
  if t.length() > 0 && t.at(0) == 124 {
    // '|' —— `///|` 块分隔符
    t = t[1:].trim_start().to_owned()
  }
  t
}

///|
/// 把源码切成 token 流。
pub fn tokenize(src : String) -> Array[Token] {
  let toks : Array[Token] = []
  let n = src.length()
  let mut i = 0
  let mut line = 1
  // 当前行是否处于“尚未出现任何有意义的 token”状态（只见过空白）。
  let mut line_blank = true
  while i < n {
    let c = src.at(i)
    // 换行
    if c == 10 || c == 13 {
      toks.push({ kind: Newline, text: "\n", start: i, end: i + 1, line, })
      i = i + 1
      if c == 13 && i < n && src.at(i) == 10 {
        i = i + 1
      }
      line = line + 1
      line_blank = true
      continue
    }
    // 空白
    if c == 32 || c == 9 {
      i = i + 1
      continue
    }
    // doc comment：仅在行首（前面只有空白）才认定为文档注释
    if line_blank &&
      c == 47 &&
      i + 2 < n &&
      src.at(i + 1) == 47 &&
      src.at(i + 2) == 47 {
      let s = i + 3
      let mut e = s
      while e < n && src.at(e) != 10 && src.at(e) != 13 {
        e = e + 1
      }
      toks.push({
        kind: Doc,
        text: normalize_doc_line(src[s:e].to_owned()),
        start: i,
        end: e,
        line,
      })
      i = e
      line_blank = true
      continue
    }
    // 普通行注释（含行中出现的 `//`）
    if c == 47 && i + 1 < n && src.at(i + 1) == 47 {
      let mut e = i
      while e < n && src.at(e) != 10 && src.at(e) != 13 {
        e = e + 1
      }
      i = e
      continue
    }
    // 原始字符串行 `#|` / `$|`：整行跳过
    if line_blank && (c == 35 || c == 36) && i + 1 < n && src.at(i + 1) == 124 {
      let mut e = i
      while e < n && src.at(e) != 10 && src.at(e) != 13 {
        e = e + 1
      }
      i = e
      line_blank = false
      continue
    }
    // 字符串字面量：跳过，处理 `\"` 转义
    if c == 34 {
      let mut e = i + 1
      while e < n {
        let d = src.at(e)
        if d == 92 {
          e = e + 2
          continue
        }
        if d == 34 {
          e = e + 1
          break
        }
        if d == 10 || d == 13 {
          break
        }
        e = e + 1
      }
      toks.push({ kind: Other, text: "\"\"", start: i, end: e, line, })
      i = e
      line_blank = false
      continue
    }
    // 字符字面量
    if c == 39 {
      let mut e = i + 1
      while e < n && src.at(e) != 39 && src.at(e) != 10 && src.at(e) != 13 {
        if src.at(e) == 92 {
          e = e + 1
        }
        e = e + 1
      }
      if e < n && src.at(e) == 39 {
        e = e + 1
      }
      toks.push({ kind: Other, text: "''", start: i, end: e, line, })
      i = e
      line_blank = false
      continue
    }
    // 标识符
    if is_ident_start(c) {
      let mut e = i
      while e < n && is_ident_continue(src.at(e)) {
        e = e + 1
      }
      toks.push({
        kind: Ident,
        text: src[i:e].to_owned(),
        start: i,
        end: e,
        line,
      })
      i = e
      line_blank = false
      continue
    }
    // 单字符符号
    let kind = if c == 40 {
      LParen
    } else if c == 41 {
      RParen
    } else if c == 91 {
      LBracket
    } else if c == 93 {
      RBracket
    } else if c == 123 {
      LBrace
    } else if c == 125 {
      RBrace
    } else if c == 44 {
      Comma
    } else if c == 58 {
      Colon
    } else if c == 63 {
      Question
    } else if c == 33 {
      Bang
    } else if c == 61 {
      Equals
    } else if c == 124 {
      Bar
    } else {
      Other
    }
    toks.push({
      kind,
      text: src[i:i + 1].to_owned(),
      start: i,
      end: i + 1,
      line,
    })
    i = i + 1
    line_blank = false
  }
  toks.push({ kind: Eof, text: "", start: n, end: n, line, })
  toks
}
