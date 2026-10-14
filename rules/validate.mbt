// 规则 validate：为类型生成 `impl Validate`。
//
// 这条规则体现派生工具的核心价值：**同一条规则，对不同类型生成不同代码**。
// 差异来自字段上的注解（@nonempty / @min / @max / @positive），
// 而不是来自规则本身的分支堆砌。
//
// 安全边界：只在**内建数值类型白名单**和 `String` 上生成检查；
// 其他类型一律跳过，并在生成文件里留下 `// moonforge:` 说明行。
// 宁可少生成，也不生成编译不过或语义可疑的代码。

///|
/// 判空检查：只对 `String` 有意义。
fn nonempty_check(td : @forge.TypeDef, f : @forge.FieldDef) -> String? {
  if f.ty != "String" {
    return None
  }
  Some(
    "  if self." +
    f.name +
    " == \"\" {\n    return Err(\"" +
    td.name +
    "." +
    f.name +
    " must not be empty\")\n  }\n",
  )
}

///|
/// 数值下界检查。
fn min_check(td : @forge.TypeDef, f : @forge.FieldDef, v : String) -> String? {
  if !@forge.is_numeric_type(f.ty) {
    return None
  }
  Some(
    "  if self." +
    f.name +
    " < " +
    v +
    " {\n    return Err(\"" +
    td.name +
    "." +
    f.name +
    " must be >= " +
    v +
    "\")\n  }\n",
  )
}

///|
/// 数值上界检查。
fn max_check(td : @forge.TypeDef, f : @forge.FieldDef, v : String) -> String? {
  if !@forge.is_numeric_type(f.ty) {
    return None
  }
  Some(
    "  if self." +
    f.name +
    " > " +
    v +
    " {\n    return Err(\"" +
    td.name +
    "." +
    f.name +
    " must be <= " +
    v +
    "\")\n  }\n",
  )
}

///|
/// 正数检查。
fn positive_check(td : @forge.TypeDef, f : @forge.FieldDef) -> String? {
  if !@forge.is_numeric_type(f.ty) {
    return None
  }
  Some(
    "  if self." +
    f.name +
    " <= 0 {\n    return Err(\"" +
    td.name +
    "." +
    f.name +
    " must be positive\")\n  }\n",
  )
}

///|
/// 一个字段上的全部检查。一个字段可以同时带多个注解（例如 `@min(0) @max(150)`），
/// 因此这里返回数组而不是单个片段。
fn field_checks(td : @forge.TypeDef, f : @forge.FieldDef) -> Array[String] {
  let out : Array[String] = []
  if f.has_attr("nonempty") {
    match nonempty_check(td, f) {
      Some(c) => out.push(c)
      None => ()
    }
  }
  if f.has_attr("positive") {
    match positive_check(td, f) {
      Some(c) => out.push(c)
      None => ()
    }
  }
  for v in f.attr_args("min") {
    match min_check(td, f, v) {
      Some(c) => out.push(c)
      None => ()
    }
  }
  for v in f.attr_args("max") {
    match max_check(td, f, v) {
      Some(c) => out.push(c)
      None => ()
    }
  }
  out
}

///|
/// 该字段是否写了“本该生成点什么”的注解 —— 用来决定要不要留说明行。
fn has_value_attr(f : @forge.FieldDef) -> Bool {
  f.has_attr("nonempty") ||
  f.has_attr("positive") ||
  f.attr_args("min").length() > 0 ||
  f.attr_args("max").length() > 0
}

///|
/// 规则类型。
pub struct ValidateRule {}

///|
pub impl @forge.DeriveRule for ValidateRule with fn head(_self) -> @forge.RuleHead {
  {
    key: "validate",
    marker: "DeriveValidate",
    trait_name: "Validate",
    description: "为 struct 实现 Validate::validate，由字段注解 @nonempty/@min/@max/@positive 驱动",
  }
}

///|
pub impl @forge.DeriveRule for ValidateRule with fn generate(_self, td) -> @forge.Fragment? {
  if !td.has_named_fields() {
    return None
  }
  let checks : Array[String] = []
  let notes : Array[String] = []
  for f in td.fields {
    let got = field_checks(td, f)
    for c in got {
      checks.push(c)
    }
    if got.length() == 0 && has_value_attr(f) {
      notes.push(
        "// moonforge: 跳过 " +
        td.name +
        "." +
        f.name +
        " 的校验注解（类型 " +
        f.ty +
        " 不在 String / 内建数值类型白名单内）\n",
      )
    }
  }
  let b = StringBuilder()
  // 只写方法名与参数：返回类型由 trait 声明（`derive/derive.mbt`）唯一决定。
  // 理由见 `rule.mbt` 的 `Fragment::impl_body`：把返回类型抄进 impl 头会让
  // `pub impl @derive.Validate for <类型名> with fn validate(self) -> Result[Unit, String] {`
  // 这一行超过 `moon fmt` 的列宽预算，格式化一次就永久报漂移。
  b.write_string("fn validate(self) {\n")
  for c in checks {
    b.write_string(c)
  }
  b.write_string("  Ok(())\n")
  b.write_string("}\n")
  Some({ notes, impl_body: b.to_string(), })
}
