// L1 单元测试：词法分析。
//
// 关注点不是“token 序列长什么样”，而是**对我方策略有影响的边界**：
// 行首判定、注释剥离、字符串/注释里的花括号不得泄漏、非 ASCII 标识符。

///|
fn idents(toks : Array[Token]) -> Array[String] {
  let out : Array[String] = []
  for t in toks {
    if t.kind == Ident {
      out.push(t.text)
    }
  }
  out
}

///|
fn doc_texts(toks : Array[Token]) -> Array[String] {
  let out : Array[String] = []
  for t in toks {
    if t.kind == Doc {
      out.push(t.text)
    }
  }
  out
}

///|
fn doc_lines(toks : Array[Token]) -> Array[Int] {
  let out : Array[Int] = []
  for t in toks {
    if t.kind == Doc {
      out.push(t.line)
    }
  }
  out
}

///|
test "词法：基本标识符顺序" {
  let src =
    #|pub struct A {
    #|  x : Int
    #|}
  @debug.debug_inspect(
    idents(tokenize(src)),
    content=(
      #|["pub", "struct", "A", "x", "Int"]
    ),
  )
}

///|
test "词法：doc comment 只认行首，并剥离 /// 与 ///| 前缀" {
  let src =
    #|///|
    #|/// @derive(field_names)
    #|struct A {
    #|  x : Int // 行内注释不是 doc
    #|}
  @debug.debug_inspect(
    doc_texts(tokenize(src)),
    content=(
      #|["", "@derive(field_names)"]
    ),
  )
}

///|
test "词法：doc comment 的行号可用于邻近性判定" {
  let src =
    #|// 普通注释
    #|/// 第一行
    #|/// 第二行
    #|struct A { x : Int }
  @debug.debug_inspect(
    doc_lines(tokenize(src)),
    content=(
      #|[2, 3]
    ),
  )
}

///|
test "词法：字符串里的花括号与 // 不参与计数" {
  let src =
    #|fn f() -> Unit {
    #|  println("{ not a brace }")
    #|  println("// not a comment")
    #|}
    #|struct B { y : Int }
  @debug.debug_inspect(
    idents(tokenize(src)),
    content=(
      #|["fn", "f", "Unit", "println", "println", "struct", "B", "y", "Int"]
    ),
  )
}

///|
test "词法：普通注释里的关键字不会被当成代码" {
  let src =
    #|// struct Fake { a : Int }
    #|struct Real { b : Int }
  @debug.debug_inspect(
    idents(tokenize(src)),
    content=(
      #|["struct", "Real", "b", "Int"]
    ),
  )
}

///|
test "词法：支持非 ASCII 标识符" {
  let src =
    #|struct 用户 {
    #|  名字 : String
    #|}
  @debug.debug_inspect(
    idents(tokenize(src)),
    content=(
      #|["struct", "用户", "名字", "String"]
    ),
  )
}

///|
test "词法：空输入只有一个 Eof 哨兵" {
  let toks = tokenize("")
  @debug.debug_inspect(
    toks.length(),
    content=(
      #|1
    ),
  )
  @debug.debug_inspect(
    toks[0].kind == Eof,
    content=(
      #|true
    ),
  )
}

///|
test "词法：tok_at 越界返回 Eof 哨兵而不是崩溃" {
  let toks = tokenize("x")
  @debug.debug_inspect(
    tok_at(toks, 999).kind == Eof,
    content=(
      #|true
    ),
  )
  @debug.debug_inspect(
    tok_at(toks, -1).kind == Eof,
    content=(
      #|true
    ),
  )
  @debug.debug_inspect(
    tok_at(toks, 0).text,
    content=(
      #|"x"
    ),
  )
}
