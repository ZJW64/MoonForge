// 语法分析：从 token 流里挑出顶层 `struct` / `enum` 定义，转成类型模型。
//
// 策略（“跳过而非解析”）：
// - 只在**花括号深度为 0** 的位置认 `struct` / `enum` 关键字，
//   因此函数体、`impl` 块、`test` 块里的同名标识不会被误判；
// - 字段类型不做语义解析，直接取源码原文切片；
// - 注解全部来自 doc comment，不引入任何语言层面的新语法。

///|
/// 一行文档注释（带行号）。行号用于判断注释是否**紧邻**声明：
/// 只有当注释最后一行恰好是声明行的前一行时才归属该声明，
/// 这样空白行就能自然切断归属，避免上一段注释泄漏到下一个声明。
pub(all) struct DocLine {
  line : Int
  text : String
} derive(Debug, Eq)

///|
/// 从文档缓冲区的尾部取“紧邻 decl_line 之前”的连续若干行，返回**正序**文本。
fn take_docs(docs : Array[DocLine], decl_line : Int) -> Array[String] {
  let rev : Array[String] = []
  let mut want = decl_line - 1
  let mut i = docs.length() - 1
  while i >= 0 && docs[i].line == want {
    rev.push(docs[i].text)
    want = want - 1
    i = i - 1
  }
  let out : Array[String] = []
  let mut k = rev.length() - 1
  while k >= 0 {
    out.push(rev[k])
    k = k - 1
  }
  out
}

///|
/// 把文档行拼成正文：丢掉空行与注解行（`@` 开头）。
fn join_doc(lines : Array[String]) -> String {
  let buf = StringBuilder()
  let mut first = true
  for l in lines {
    let t = l.trim().to_owned()
    if t.length() > 0 && !t.has_prefix("@") {
      if !first {
        buf.write_string("\n")
      }
      buf.write_string(t)
      first = false
    }
  }
  buf.to_string()
}

///|
/// 按逗号切分注解参数，忽略括号/方括号内部的逗号。
fn split_args(inner : String) -> Array[String] {
  let out : Array[String] = []
  let buf = StringBuilder()
  let n = inner.length()
  let mut depth = 0
  let mut i = 0
  while i < n {
    let c = inner.at(i)
    if c == 40 || c == 91 {
      depth = depth + 1
    } else if c == 41 || c == 93 {
      if depth > 0 {
        depth = depth - 1
      }
    }
    if c == 44 && depth == 0 {
      out.push(buf.to_string().trim().to_owned())
      buf.reset()
    } else {
      // 注意：不要用 `write_substring(buf, i, i + 1)` —— 它的第三个参数是
      // 长度而不是结束偏移。这里用单码元视图，语义直接。
      buf.write_stringview(inner[i:i + 1])
    }
    i = i + 1
  }
  let last = buf.to_string().trim().to_owned()
  if last.length() > 0 {
    out.push(last)
  }
  out
}

///|
/// 在一行文本里扫描 `@name` / `@name(arg, ...)`。
///
/// 只接受行首或空白之后的 `@`，因此 `foo@bar.com` 不会被误判成注解。
fn scan_attrs(line : String) -> Array[Attr] {
  let out : Array[Attr] = []
  let n = line.length()
  let mut i = 0
  while i < n {
    if line.at(i) == 64 {
      let prev_ok = i == 0 || line.at(i - 1) == 32 || line.at(i - 1) == 9
      if prev_ok {
        let ns = i + 1
        let mut j = ns
        while j < n {
          let c = line.at(j)
          let ok = (c >= 65 && c <= 90) ||
            (c >= 97 && c <= 122) ||
            c == 95 ||
            (c >= 48 && c <= 57)
          if !ok {
            break
          }
          j = j + 1
        }
        if j > ns {
          let name = line[ns:j].to_owned()
          let mut args : Array[String] = []
          let mut k = j
          if k < n && line.at(k) == 40 {
            let arg_start = k + 1
            let mut d = 0
            let mut m = k
            while m < n {
              let c = line.at(m)
              if c == 40 {
                d = d + 1
              } else if c == 41 {
                d = d - 1
                if d == 0 {
                  break
                }
              }
              m = m + 1
            }
            args = split_args(line[arg_start:m].to_owned())
            k = m + 1
          }
          out.push({ name, args })
          i = k
          continue
        }
      }
    }
    i = i + 1
  }
  out
}

///|
/// 收集多行文档里的全部注解（保持书写顺序）。
fn attrs_of(lines : Array[String]) -> Array[Attr] {
  let out : Array[Attr] = []
  for l in lines {
    for a in scan_attrs(l) {
      out.push(a)
    }
  }
  out
}

///|
/// 清理字段类型原文：去首尾空白，并丢掉行尾的 `//` 注释。
fn clean_type_text(raw : String) -> String {
  let t = raw.trim().to_owned()
  match t.find("//") {
    Some(i) => t[0:i].trim().to_owned()
    None => t
  }
}

///|
/// 从 `start` 处的开括号跳到配对闭括号之后；用于跳过 `[T, U]` 泛型参数等。
fn skip_balanced(
  toks : Array[Token],
  start : Int,
  open_kind : TokKind,
  close_kind : TokKind,
) -> Int {
  let mut j = start
  let mut d = 0
  while j < toks.length() {
    let k = tok_at(toks, j).kind
    if k == open_kind {
      d = d + 1
    } else if k == close_kind {
      d = d - 1
      if d == 0 {
        return j + 1
      }
    } else if k == Eof {
      return j
    }
    j = j + 1
  }
  j
}

///|
/// 解析单个类型声明。返回 (类型定义, 声明结束后的下一个 token 下标)。
fn parse_type_decl(
  src : String,
  toks : Array[Token],
  kw_index : Int,
  docs : Array[DocLine],
  line_start_off : Int,
) -> (TypeDef, Int) {
  let kw = tok_at(toks, kw_index)
  let is_enum = kw.text == "enum"
  let line_prefix = src[line_start_off:kw.start].to_owned()
  let is_pub = line_prefix.trim_start().has_prefix("pub")
  let own_docs = take_docs(docs, kw.line)
  let doc = join_doc(own_docs)
  let attrs = attrs_of(own_docs)
  let kind = if is_enum {
    TEnum
  } else {
    TStruct
  }
  let mut j = kw_index + 1
  while tok_at(toks, j).kind == Newline {
    j = j + 1
  }
  let name = tok_at(toks, j).text
  j = j + 1
  if tok_at(toks, j).kind == LBracket {
    j = skip_balanced(toks, j, LBracket, RBracket)
  }
  while j < toks.length() {
    let k = tok_at(toks, j).kind
    if k == LBrace || k == Eof {
      break
    }
    j = j + 1
  }
  let fields : Array[FieldDef] = []
  let variants : Array[String] = []
  if tok_at(toks, j).kind == LBrace {
    j = j + 1
    while j < toks.length() {
      let t = tok_at(toks, j)
      match t.kind {
        RBrace => {
          j = j + 1
          break
        }
        Eof => break
        Newline | Comma | Bar => j = j + 1
        Doc => {
          // 结构体体内的注释也必须进缓冲，否则字段注解无从归属。
          docs.push({ line: t.line, text: t.text })
          j = j + 1
        }
        Ident => {
          if is_enum {
            variants.push(t.text)
            j = j + 1
          } else {
            let fname = t.text
            let fline = t.line
            let mut k = j + 1
            while tok_at(toks, k).kind == Newline {
              k = k + 1
            }
            if tok_at(toks, k).kind == Colon {
              k = k + 1
              let tstart = tok_at(toks, k).start
              let mut tend = tstart
              let mut d2 = 0
              while k < toks.length() {
                let tk = tok_at(toks, k)
                match tk.kind {
                  LBracket | LParen => {
                    d2 = d2 + 1
                    tend = tk.end
                    k = k + 1
                  }
                  RBracket | RParen => {
                    if d2 > 0 {
                      d2 = d2 - 1
                    }
                    tend = tk.end
                    k = k + 1
                  }
                  Newline => {
                    if d2 <= 0 {
                      break
                    }
                    k = k + 1
                  }
                  RBrace | Eof => break
                  _ => {
                    tend = tk.end
                    k = k + 1
                  }
                }
              }
              let fdocs = take_docs(docs, fline)
              fields.push({
                name: fname,
                ty: clean_type_text(src[tstart:tend].to_owned()),
                doc: join_doc(fdocs),
                attrs: attrs_of(fdocs),
                line: fline,
              })
              j = k
            } else {
              j = j + 1
            }
          }
        }
        _ => j = j + 1
      }
    }
  }
  (
    {
      name,
      kind,
      is_pub,
      fields,
      variants,
      doc,
      attrs,
      line: kw.line,
    },
    j,
  )
}

///|
/// 解析一份 MoonBit 源码，返回其中所有顶层类型定义（保持源码顺序）。
pub fn parse_source(src : String) -> Array[TypeDef] {
  let toks = tokenize(src)
  let out : Array[TypeDef] = []
  let docs : Array[DocLine] = []
  let n = toks.length()
  let mut i = 0
  let mut depth = 0
  let mut line_start_off = 0
  while i < n {
    let t = tok_at(toks, i)
    match t.kind {
      Doc => {
        // 空行（`///`、`///|`）也要入缓冲，否则行号连续性被打断，
        // 会导致注释归属判定提前终止。空文本在 `join_doc` 里会被丢掉。
        docs.push({ line: t.line, text: t.text })
        i = i + 1
      }
      Newline => {
        line_start_off = t.end
        i = i + 1
      }
      LBrace => {
        depth = depth + 1
        i = i + 1
      }
      RBrace => {
        if depth > 0 {
          depth = depth - 1
        }
        i = i + 1
      }
      Ident => {
        if depth == 0 && (t.text == "struct" || t.text == "enum") {
          let (td, next) = parse_type_decl(src, toks, i, docs, line_start_off)
          out.push(td)
          i = next
        } else {
          i = i + 1
        }
      }
      Eof => break
      _ => i = i + 1
    }
  }
  out
}
