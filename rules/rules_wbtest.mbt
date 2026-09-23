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
      #|["field_names", "validate", "diff"]
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
