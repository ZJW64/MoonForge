// L3 规则测试：三条内置规则各自的行为与边界。
//
// 每条规则至少覆盖：正常路径、不适用路径（enum / 类型不在白名单）、
// 以及“为什么不生成”的说明行。

///|
fn apply_rule(name : String, src : String) -> String? {
  let td = @forge.parse_source(src)[0]
  match @forge.find_rule(all(), name) {
    Some(r) => r.apply(td)
    None => None
  }
}

///|
fn lines_of(s : String) -> Array[String] {
  let out : Array[String] = []
  for l in s.split("\n") {
    out.push(l.to_owned())
  }
  out
}

///|
test "注册表：三条内置规则都已注册且名字合法" {
  @debug.debug_inspect(
    @forge.rule_names(all()),
    content=(
      #|["field_names", "validate", "diff", "to_pairs"]
    ),
  )
  for r in all() {
    @debug.debug_inspect(
      @forge.is_valid_rule_name(r.name),
      content=(
        #|true
      ),
    )
  }
}

///|
test "field_names：struct 正常生成" {
  let src =
    #|struct A {
    #|  x : Int
    #|  y : String
    #|}
  @debug.debug_inspect(
    apply_rule("field_names", src),
    content=(
      #|Some("///|\npub fn A::field_names() -> Array[String] {\n  [\"x\", \"y\"]\n}\n")
    ),
  )
}

///|
test "field_names：空字段的 struct 也要生成（边界）" {
  @debug.debug_inspect(
    apply_rule("field_names", "struct Empty {}"),
    content=(
      #|Some("///|\npub fn Empty::field_names() -> Array[String] {\n  []\n}\n")
    ),
  )
}

///|
test "field_names：enum 不适用 → None" {
  @debug.debug_inspect(
    apply_rule("field_names", "enum E { A; B }") is None,
    content=(
      #|true
    ),
  )
}

///|
test "field_names：非 ASCII 字段名" {
  let src =
    #|struct 用户 {
    #|  名字 : String
    #|}
  @debug.debug_inspect(
    apply_rule("field_names", src),
    content=(
      #|Some("///|\npub fn 用户::field_names() -> Array[String] {\n  [\"名字\"]\n}\n")
    ),
  )
}

///|
test "validate：@nonempty 只对 String 生效（Int 字段被跳过并留说明）" {
  let src =
    #|struct A {
    #|  s : String
    #|  /// @nonempty
    #|  i : Int
    #|}
  @debug.debug_inspect(
    apply_rule("validate", src),
    content=(
      #|Some("// moonforge: 跳过 A.i 的校验注解（类型 Int 不在 String / 内建数值类型白名单内）\n\n///|\npub fn A::validate(self : A) -> Result[Unit, String] {\n  Ok(())\n}\n")
    ),
  )
}

///|
test "validate：@nonempty / @min / @max / @positive 组合" {
  let src =
    #|struct A {
    #|  /// @nonempty
    #|  name : String
    #|  /// @min(0) @max(150)
    #|  age : Int
    #|  /// @positive
    #|  amount : Int64
    #|  /// @min(-10)
    #|  delta : Double
    #|}
  @debug.debug_inspect(
    apply_rule("validate", src),
    content=(
      #|Some("///|\npub fn A::validate(self : A) -> Result[Unit, String] {\n  if self.name == \"\" {\n    return Err(\"A.name must not be empty\")\n  }\n  if self.age < 0 {\n    return Err(\"A.age must be >= 0\")\n  }\n  if self.age > 150 {\n    return Err(\"A.age must be <= 150\")\n  }\n  if self.amount <= 0 {\n    return Err(\"A.amount must be positive\")\n  }\n  if self.delta < -10 {\n    return Err(\"A.delta must be >= -10\")\n  }\n  Ok(())\n}\n")
    ),
  )
}

///|
test "validate：白名单之外的类型会跳过并留下说明行" {
  let src =
    #|struct A {
    #|  /// @nonempty
    #|  weird : Array[String]
    #|}
  @debug.debug_inspect(
    apply_rule("validate", src),
    content=(
      #|Some("// moonforge: 跳过 A.weird 的校验注解（类型 Array[String] 不在 String / 内建数值类型白名单内）\n\n///|\npub fn A::validate(self : A) -> Result[Unit, String] {\n  Ok(())\n}\n")
    ),
  )
}

///|
test "validate：无注解字段不产生任何检查" {
  let src =
    #|struct A {
    #|  a : String
    #|  b : Int
    #|}
  @debug.debug_inspect(
    apply_rule("validate", src),
    content=(
      #|Some("///|\npub fn A::validate(self : A) -> Result[Unit, String] {\n  Ok(())\n}\n")
    ),
  )
}

///|
test "validate：enum 不适用 → None" {
  @debug.debug_inspect(
    apply_rule("validate", "enum E { A }") is None,
    content=(
      #|true
    ),
  )
}

///|
test "diff：逐字段展开" {
  let src =
    #|struct A {
    #|  x : Int
    #|  y : String
    #|}
  @debug.debug_inspect(
    apply_rule("diff", src),
    content=(
      #|Some("///|\npub fn A::diff(self : A, other : A) -> Array[String] {\n  let changed : Array[String] = []\n  if self.x != other.x {\n    changed.push(\"x\")\n  }\n  if self.y != other.y {\n    changed.push(\"y\")\n  }\n  changed\n}\n")
    ),
  )
}

///|
test "diff：空 struct 也是合法的（返回空数组）" {
  @debug.debug_inspect(
    apply_rule("diff", "struct Empty {}"),
    content=(
      #|Some("///|\npub fn Empty::diff(self : Empty, other : Empty) -> Array[String] {\n  let changed : Array[String] = []\n  changed\n}\n")
    ),
  )
}

///|
test "diff：enum 不适用 → None" {
  @debug.debug_inspect(
    apply_rule("diff", "enum E { A }") is None,
    content=(
      #|true
    ),
  )
}

///|
test "集成：完整源码 → 完整生成文件（金样）" {
  let src =
    #|/// 用户
    #|/// @derive(field_names, validate, diff)
    #|pub(all) struct User {
    #|  /// @nonempty
    #|  name : String
    #|  /// @min(0) @max(150)
    #|  age : Int
    #|  email : String
    #|}
    #|
    #|/// 没有标记 → 不产出
    #|struct Plain { a : Int }
    #|
    #|/// @derive(validate)
    #|enum Status { On; Off }
  let out = @forge.generate("t.mbt", src, all(), @forge.MOONFORGE_VERSION)
  @debug.debug_inspect(
    lines_of(out.text),
    content=(
      #|[
      #|  "// ---------------------------------------------------------------------------",
      #|  "// Generated by MoonForge 0.1.0 -- DO NOT EDIT.",
      #|  "// source : t.mbt",
      #|  "// rules  : field_names, validate, diff",
      #|  "// regen  : moon run cmd/main -- gen <dir>",
      #|  "// ---------------------------------------------------------------------------",
      #|  "",
      #|  "///|",
      #|  "pub fn User::field_names() -> Array[String] {",
      #|  "  [\"name\", \"age\", \"email\"]",
      #|  "}",
      #|  "",
      #|  "///|",
      #|  "pub fn User::validate(self : User) -> Result[Unit, String] {",
      #|  "  if self.name == \"\" {",
      #|  "    return Err(\"User.name must not be empty\")",
      #|  "  }",
      #|  "  if self.age < 0 {",
      #|  "    return Err(\"User.age must be >= 0\")",
      #|  "  }",
      #|  "  if self.age > 150 {",
      #|  "    return Err(\"User.age must be <= 150\")",
      #|  "  }",
      #|  "  Ok(())",
      #|  "}",
      #|  "",
      #|  "///|",
      #|  "pub fn User::diff(self : User, other : User) -> Array[String] {",
      #|  "  let changed : Array[String] = []",
      #|  "  if self.name != other.name {",
      #|  "    changed.push(\"name\")",
      #|  "  }",
      #|  "  if self.age != other.age {",
      #|  "    changed.push(\"age\")",
      #|  "  }",
      #|  "  if self.email != other.email {",
      #|  "    changed.push(\"email\")",
      #|  "  }",
      #|  "  changed",
      #|  "}",
      #|  "",
      #|]
    ),
  )
  @debug.debug_inspect(
    out.applied,
    content=(
      #|["User.field_names", "User.validate", "User.diff"]
    ),
  )
  @debug.debug_inspect(
    out.diagnostics,
    content=(
      #|["规则 `validate` 不适用于 Status（第 15 行）：该规则只支持 struct 定义"]
    ),
  )
}

///|
test "三条规则都对位置参数结构体返回 None（没有字段名可展开）" {
  // `struct P(Int, Int)` 在 TypeKind 上仍是 TStruct。如果规则只用
  // `is_enum()` 做前置判断，就会为它生成 `field_names() { [] }` ——
  // 语法上说得通、语义上完全错误，而且编译器不会报错。
  let positional =
    #|/// @derive(field_names, validate, diff)
    #|pub struct P(Int, Int)
  for name in ["field_names", "validate", "diff"] {
    @debug.debug_inspect(
      apply_rule(name, positional) is None,
      content=(
        #|true
      ),
    )
  }
}

///|
test "三条规则都对没有字段体的声明返回 None" {
  let bodyless =
    #|/// @derive(field_names, validate, diff)
    #|struct O
  for name in ["field_names", "validate", "diff"] {
    @debug.debug_inspect(
      apply_rule(name, bodyless) is None,
      content=(
        #|true
      ),
    )
  }
}

///|
test "validate：尾随逗号不再让 @nonempty 被静默跳过" {
  // 修复前字段类型会被切成 "String,"，白名单命中失败 → 校验被跳过并留下
  // 一条"跳过"说明行。修复后类型是干净的 "String"，检查正常生成。
  let src =
    #|struct A {
    #|  /// @nonempty
    #|  a : String,
    #|}
  @debug.debug_inspect(
    apply_rule("validate", src),
    content=(
      #|Some("///|\npub fn A::validate(self : A) -> Result[Unit, String] {\n  if self.a == \"\" {\n    return Err(\"A.a must not be empty\")\n  }\n  Ok(())\n}\n")
    ),
  )
}

///|
test "validate：跨行书写的字段类型仍能命中数值白名单" {
  // 类型原文里的换行会被折叠成空格。若折叠成 "Int " 之类的形状，
  // 白名单命中就会失败 —— 这里把它固定下来。
  let src =
    #|struct A {
    #|  /// @min(0)
    #|  n : Int
    #|}
  @debug.debug_inspect(
    apply_rule("validate", src),
    content=(
      #|Some("///|\npub fn A::validate(self : A) -> Result[Unit, String] {\n  if self.n < 0 {\n    return Err(\"A.n must be >= 0\")\n  }\n  Ok(())\n}\n")
    ),
  )
}

///|
test "to_pairs：只收 String 字段，其余字段留说明行" {
  let src =
    #|struct User {
    #|  name : String
    #|  age : Int
    #|  email : String
    #|}
  @debug.debug_inspect(
    apply_rule("to_pairs", src),
    content=(
      #|Some("// moonforge: 跳过 User.age 的 to_pairs（类型 Int 不是 String；如何转成字符串由使用者决定）\n\n///|\npub fn User::to_pairs(self : User) -> Array[(String, String)] {\n  [(\"name\", self.name), (\"email\", self.email)]\n}\n")
    ),
  )
}

///|
test "to_pairs：一个 String 字段都没有时产出空数组（仍然能编译）" {
  let src =
    #|struct AllInt {
    #|  a : Int
    #|}
  @debug.debug_inspect(
    apply_rule("to_pairs", src),
    content=(
      #|Some("// moonforge: 跳过 AllInt.a 的 to_pairs（类型 Int 不是 String；如何转成字符串由使用者决定）\n\n///|\npub fn AllInt::to_pairs(self : AllInt) -> Array[(String, String)] {\n  []\n}\n")
    ),
  )
}

///|
test "to_pairs：字段顺序决定输出顺序，且没有 String 字段时不留空行" {
  let src =
    #|struct P {
    #|  b : String
    #|  a : String
    #|}
  @debug.debug_inspect(
    apply_rule("to_pairs", src),
    content=(
      #|Some("///|\npub fn P::to_pairs(self : P) -> Array[(String, String)] {\n  [(\"b\", self.b), (\"a\", self.a)]\n}\n")
    ),
  )
}

///|
test "to_pairs：枚举与位置参数结构体都返回 None" {
  @debug.debug_inspect(
    apply_rule("to_pairs", "enum E { A }") is None,
    content=(
      #|true
    ),
  )
  @debug.debug_inspect(
    apply_rule("to_pairs", "struct P(Int, Int)") is None,
    content=(
      #|true
    ),
  )
}

///|
test "to_pairs：nullable 与泛型字段不会被误当成 String" {
  let src =
    #|struct A {
    #|  s : String
    #|  ns : String?
    #|  arr : Array[String]
    #|}
  @debug.debug_inspect(
    apply_rule("to_pairs", src),
    content=(
      #|Some("// moonforge: 跳过 A.ns 的 to_pairs（类型 String? 不是 String；如何转成字符串由使用者决定）\n// moonforge: 跳过 A.arr 的 to_pairs（类型 Array[String] 不是 String；如何转成字符串由使用者决定）\n\n///|\npub fn A::to_pairs(self : A) -> Array[(String, String)] {\n  [(\"s\", self.s)]\n}\n")
    ),
  )
}
