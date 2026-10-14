// L3 规则测试：四条内置规则各自的行为与边界。
//
// 每条规则至少覆盖：正常路径、不适用路径（enum / 位置参数 / 无字段体）、
// 以及"为什么不生成"的说明行。
//
// 断言用**文本相等**（`assert_eq`）而不是 `inspect` 的数组渲染：
// 数组的渲染会按宽度折行 —— 短数组单行、长数组多行，金样会随内容长度
// 忽然变红或变绿。文本比较没有这个自由度，失败时 `assert_eq` 照样给 diff。

///|
/// 直接调用某条规则的生成函数（绕开标记解析，专注规则本身）。
fn frag_of(key : String, src : String) -> @forge.Fragment? {
  let td = @forge.parse_source(src)[0]
  match @forge.find_rule(all(), key) {
    Some(r) => r.generate(td)
    None => None
  }
}

///|
/// 把「一行一段」拼成带尾换行的文本 —— 与生成器的组装方式一致。
fn code(lines : Array[String]) -> String {
  lines.join("\n") + "\n"
}

///|
/// 规则的成员文本；不适用时返回一个显眼的哨兵，
/// 让"本该适用却不适用"这类回归一眼可见。
fn body_text(key : String, src : String) -> String {
  match frag_of(key, src) {
    Some(f) => f.impl_body
    None => "<不适用>"
  }
}

///|
/// 说明行拼成文本（去掉末尾换行），无说明行时是空串。
fn notes_text(key : String, src : String) -> String {
  let b = StringBuilder()
  match frag_of(key, src) {
    Some(f) =>
      for n in f.notes {
        b.write_string(n)
      }
    None => ()
  }
  let s = b.to_string()
  if s.has_suffix("\n") {
    s[0:s.length() - 1].to_owned()
  } else {
    s
  }
}

// ---------------------------------------------------------------------------
// 注册表
// ---------------------------------------------------------------------------

///|
test "注册表：四条内置规则都已注册，键名合法、标记名成对" {
  @debug.debug_inspect(
    @forge.rule_keys(all()),
    content="[\"field_names\", \"validate\", \"diff\", \"to_pairs\"]",
  )
  @debug.debug_inspect(
    @forge.marker_names(all()),
    content="[\"DeriveFieldNames\", \"DeriveValidate\", \"DeriveDiff\", \"DeriveToPairs\"]",
  )
  for r in all() {
    @debug.debug_inspect(
      @forge.is_valid_rule_name(@forge.key_of(r)),
      content="true",
    )
    // 标记 trait 统一以 Derive 开头，命名可预测 —— 用户不必查文档就能猜出来。
    @debug.debug_inspect(
      @forge.marker_of(r).has_prefix("Derive"),
      content="true",
    )
    @debug.debug_inspect(
      @forge.find_rule_by_marker(all(), @forge.marker_of(r)) is Some(_),
      content="true",
    )
  }
}

// ---------------------------------------------------------------------------
// field_names
// ---------------------------------------------------------------------------

///|
test "field_names：struct 正常生成" {
  let src =
    #|struct A {
    #|  x : Int
    #|  y : String
    #|}
  assert_eq(
    body_text("field_names", src),
    code(["fn field_names(_self) {", "  [\"x\", \"y\"]", "}"]),
  )
  assert_eq(notes_text("field_names", src), "")
}

///|
test "field_names：空字段的 struct 也要生成（边界）" {
  assert_eq(
    body_text("field_names", "struct Empty {}"),
    code(["fn field_names(_self) {", "  []", "}"]),
  )
}

///|
test "field_names：enum 不适用 → None" {
  @debug.debug_inspect(
    frag_of("field_names", "enum E { A; B }") is None,
    content="true",
  )
}

///|
test "field_names：非 ASCII 字段名" {
  let src =
    #|struct 用户 {
    #|  名字 : String
    #|}
  assert_eq(
    body_text("field_names", src),
    code(["fn field_names(_self) {", "  [\"名字\"]", "}"]),
  )
}

// ---------------------------------------------------------------------------
// validate
// ---------------------------------------------------------------------------

///|
test "validate：@nonempty 只对 String 生效（Int 字段被跳过并留说明）" {
  let src =
    #|struct A {
    #|  s : String
    #|  /// @nonempty
    #|  i : Int
    #|}
  assert_eq(
    notes_text("validate", src),
    "// moonforge: 跳过 A.i 的校验注解（类型 Int 不在 String / 内建数值类型白名单内）",
  )
  assert_eq(
    body_text("validate", src),
    code(["fn validate(self) {", "  Ok(())", "}"]),
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
  assert_eq(
    body_text("validate", src),
    code([
      "fn validate(self) {", "  if self.name == \"\" {", "    return Err(\"A.name must not be empty\")",
      "  }", "  if self.age < 0 {", "    return Err(\"A.age must be >= 0\")", "  }",
      "  if self.age > 150 {", "    return Err(\"A.age must be <= 150\")", "  }",
      "  if self.amount <= 0 {", "    return Err(\"A.amount must be positive\")",
      "  }", "  if self.delta < -10 {", "    return Err(\"A.delta must be >= -10\")",
      "  }", "  Ok(())", "}",
    ]),
  )
}

///|
test "validate：白名单之外的类型会跳过并留下说明行" {
  let src =
    #|struct A {
    #|  /// @nonempty
    #|  weird : Array[String]
    #|}
  assert_eq(
    notes_text("validate", src),
    "// moonforge: 跳过 A.weird 的校验注解（类型 Array[String] 不在 String / 内建数值类型白名单内）",
  )
  assert_eq(
    body_text("validate", src),
    code(["fn validate(self) {", "  Ok(())", "}"]),
  )
}

///|
test "validate：无注解字段不产生任何检查" {
  let src =
    #|struct A {
    #|  a : String
    #|  b : Int
    #|}
  assert_eq(
    body_text("validate", src),
    code(["fn validate(self) {", "  Ok(())", "}"]),
  )
  assert_eq(notes_text("validate", src), "")
}

///|
test "validate：enum 不适用 → None" {
  @debug.debug_inspect(
    frag_of("validate", "enum E { A }") is None,
    content="true",
  )
}

// ---------------------------------------------------------------------------
// diff
// ---------------------------------------------------------------------------

///|
test "diff：逐字段展开" {
  let src =
    #|struct A {
    #|  x : Int
    #|  y : String
    #|}
  assert_eq(
    body_text("diff", src),
    code([
      "fn diff(self, other) {", "  let changed : Array[String] = []", "  if self.x != other.x {",
      "    changed.push(\"x\")", "  }", "  if self.y != other.y {", "    changed.push(\"y\")",
      "  }", "  changed", "}",
    ]),
  )
}

///|
test "diff：空 struct 也是合法的（返回空数组）" {
  assert_eq(
    body_text("diff", "struct Empty {}"),
    code([
      "fn diff(self, other) {", "  let changed : Array[String] = []", "  changed",
      "}",
    ]),
  )
}

///|
test "diff：enum 不适用 → None" {
  @debug.debug_inspect(frag_of("diff", "enum E { A }") is None, content="true")
}

// ---------------------------------------------------------------------------
// to_pairs
// ---------------------------------------------------------------------------

///|
test "to_pairs：只收 String 字段，其余字段留说明行" {
  let src =
    #|struct User {
    #|  name : String
    #|  age : Int
    #|  email : String
    #|}
  assert_eq(
    notes_text("to_pairs", src),
    "// moonforge: 跳过 User.age 的 to_pairs（类型 Int 不是 String；如何转成字符串由使用者决定）",
  )
  assert_eq(
    body_text("to_pairs", src),
    code([
      "fn to_pairs(self) {", "  [(\"name\", self.name), (\"email\", self.email)]",
      "}",
    ]),
  )
}

///|
test "to_pairs：一个 String 字段都没有时产出空数组（仍然能编译）" {
  assert_eq(
    body_text("to_pairs", "struct AllInt {\n  a : Int\n}"),
    code(["fn to_pairs(self) {", "  []", "}"]),
  )
  @debug.debug_inspect(
    notes_text("to_pairs", "struct AllInt {\n  a : Int\n}").length() > 0,
    content="true",
  )
}

///|
test "to_pairs：字段顺序决定输出顺序" {
  let src =
    #|struct P {
    #|  b : String
    #|  a : String
    #|}
  assert_eq(
    body_text("to_pairs", src),
    code(["fn to_pairs(self) {", "  [(\"b\", self.b), (\"a\", self.a)]", "}"]),
  )
  assert_eq(notes_text("to_pairs", src), "")
}

///|
test "to_pairs：枚举与位置参数结构体都返回 None" {
  @debug.debug_inspect(
    frag_of("to_pairs", "enum E { A }") is None,
    content="true",
  )
  @debug.debug_inspect(
    frag_of("to_pairs", "struct P(Int, Int)") is None,
    content="true",
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
  assert_eq(
    body_text("to_pairs", src),
    code(["fn to_pairs(self) {", "  [(\"s\", self.s)]", "}"]),
  )
  // 两条说明行：ns 与 arr 各一条
  assert_eq(
    notes_text("to_pairs", src),
    code([
      "// moonforge: 跳过 A.ns 的 to_pairs（类型 String? 不是 String；如何转成字符串由使用者决定）",
      "// moonforge: 跳过 A.arr 的 to_pairs（类型 Array[String] 不是 String；如何转成字符串由使用者决定）",
    ])
    .trim()
    .to_owned(),
  )
}

// ---------------------------------------------------------------------------
// 跨规则：不适用路径必须一致
// ---------------------------------------------------------------------------

///|
test "四条规则都对位置参数结构体返回 None（没有字段名可展开）" {
  // `struct P(Int, Int)` 在 TypeKind 上仍是 TStruct。如果规则只用
  // `is_enum()` 做前置判断，就会为它生成一个返回空数组的 field_names ——
  // 语法上说得通、语义上完全错误，而且编译器不会报错。
  for name in ["field_names", "validate", "diff", "to_pairs"] {
    @debug.debug_inspect(
      frag_of(name, "pub struct P(Int, Int)") is None,
      content="true",
    )
  }
}

///|
test "四条规则都对没有字段体的声明返回 None" {
  for name in ["field_names", "validate", "diff", "to_pairs"] {
    @debug.debug_inspect(frag_of(name, "struct O") is None, content="true")
  }
}

// ---------------------------------------------------------------------------
// 白名单边界的回归
// ---------------------------------------------------------------------------

///|
test "validate：尾随逗号不再让 @nonempty 被静默跳过" {
  // 修复前字段类型会被切成 "String,"，白名单命中失败 → 校验被跳过并留下
  // 一条"跳过"说明行。修复后类型是干净的 "String"，检查正常生成。
  let src =
    #|struct A {
    #|  /// @nonempty
    #|  a : String,
    #|}
  assert_eq(
    body_text("validate", src),
    code([
      "fn validate(self) {", "  if self.a == \"\" {", "    return Err(\"A.a must not be empty\")",
      "  }", "  Ok(())", "}",
    ]),
  )
  assert_eq(notes_text("validate", src), "")
}

///|
test "validate：@min 在数值字段上正常生成" {
  let src =
    #|struct A {
    #|  /// @min(0)
    #|  n : Int
    #|}
  assert_eq(
    body_text("validate", src),
    code([
      "fn validate(self) {", "  if self.n < 0 {", "    return Err(\"A.n must be >= 0\")",
      "  }", "  Ok(())", "}",
    ]),
  )
}

// ---------------------------------------------------------------------------
// 集成金样：新入口 → 完整生成文件
// ---------------------------------------------------------------------------

///|
test "集成：完整源码 → 完整生成文件（金样）" {
  let src =
    #|/// 用户
    #|pub(all) struct User {
    #|  /// @nonempty
    #|  name : String
    #|  /// @min(0) @max(150)
    #|  age : Int
    #|  email : String
    #|}
    #|
    #|///|
    #|pub impl @derive.DeriveFieldNames for User with fn requested(_self) {}
    #|
    #|///|
    #|pub impl @derive.DeriveValidate for User with fn requested(_self) {}
    #|
    #|///|
    #|pub impl @derive.DeriveDiff for User with fn requested(_self) {}
    #|
    #|/// 没有标记 → 不产出
    #|struct Plain {
    #|  a : Int
    #|}
    #|
    #|pub enum Status {
    #|  On
    #|  Off
    #|}
    #|
    #|///|
    #|pub impl @derive.DeriveValidate for Status with fn requested(_self) {}
  let out = @forge.generate("t.mbt", src, all(), @forge.MOONFORGE_VERSION)
  // 文件头单独断言，版本号取自 `@forge.MOONFORGE_VERSION`。
  // 把版本写死在金样里，发一次版金样就红 —— 那是金样错了，不是实现错了：
  // 版本号本来就有唯一来源，金样不该再抄一份。
  let header = "// ---------------------------------------------------------------------------\n" +
    "// Generated by MoonForge " +
    @forge.MOONFORGE_VERSION +
    " -- DO NOT EDIT.\n" +
    "// source : t.mbt\n" +
    "// rules  : field_names, validate, diff\n" +
    "// entry  : impl @derive.DeriveXxx for <Type> with fn requested(_self) {}\n" +
    "// regen  : moon run cmd/main -- gen <dir>\n" +
    "// ---------------------------------------------------------------------------\n"
  @debug.debug_inspect(out.text.has_prefix(header), content="true")
  assert_eq(
    out.text[header.length():].to_owned(),
    code([
      "", "///|", "pub impl @derive.FieldNames for User with fn field_names(_self) {",
      "  [\"name\", \"age\", \"email\"]", "}", "", "///|", "pub impl @derive.Validate for User with fn validate(self) {",
      "  if self.name == \"\" {", "    return Err(\"User.name must not be empty\")",
      "  }", "  if self.age < 0 {", "    return Err(\"User.age must be >= 0\")",
      "  }", "  if self.age > 150 {", "    return Err(\"User.age must be <= 150\")",
      "  }", "  Ok(())", "}", "", "///|", "pub impl @derive.Diff for User with fn diff(self, other) {",
      "  let changed : Array[String] = []", "  if self.name != other.name {", "    changed.push(\"name\")",
      "  }", "  if self.age != other.age {", "    changed.push(\"age\")", "  }",
      "  if self.email != other.email {", "    changed.push(\"email\")", "  }", "  changed",
      "}",
    ]),
  )
  @debug.debug_inspect(
    out.applied,
    content="[\"User.field_names\", \"User.validate\", \"User.diff\"]",
  )
  assert_eq(out.diagnostics, [
    "规则 `validate` 不适用于 Status（第 30 行）：该规则只支持 struct 定义",
  ])
}
