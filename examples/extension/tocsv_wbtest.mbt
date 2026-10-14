// 第三方规则的用例：证明「不改 moonforge 源码也能加规则」不是口号。

///|
fn contains_text(hay : String, needle : String) -> Bool {
  match hay.find(needle) {
    Some(_) => true
    None => false
  }
}

///|
test "第三方规则：不改 moonforge 源码即可注册并生效" {
  let src =
    #|///|
    #|pub struct Row {
    #|  a : String
    #|  n : Int
    #|}
    #|
    #|///|
    #|pub impl @ext.DeriveToCsv for Row with fn requested(_self) {}
  let out = generate_with_extension("row.mbt", src)
  @debug.debug_inspect(out.has_output, content="true")
  @debug.debug_inspect(out.applied, content="[\"Row.to_csv\"]")
  @debug.debug_inspect(out.diagnostics, content="[]")
  // 生成物里的 impl 头复用了用户写标记时用的包前缀 `@ext`，
  // 因此第三方把包起什么别名都不会被工具改掉。
  @debug.debug_inspect(
    contains_text(
      out.text,
      "pub impl @ext.ToCsv for Row with fn to_csv(self) {",
    ),
    content="true",
  )
  // 白名单纪律对第三方规则同样适用：Int 字段被跳过，并留下说明行。
  @debug.debug_inspect(
    contains_text(out.text, "跳过 Row.n 的 to_csv"),
    content="true",
  )
}

///|
test "手写 impl 与生成物形状一致：生成的 to_csv 确实可编译可调用" {
  let s : Sample = { host: "example.com", port: 80, }
  @debug.debug_inspect(ToCsv::to_csv(s), content="\"example.com\"")
}

///|
test "扩展规则集与内置规则可共存于同一次生成" {
  let src =
    #|///|
    #|pub struct Row {
    #|  a : String
    #|}
    #|
    #|///|
    #|pub impl @ext.DeriveToCsv for Row with fn requested(_self) {}
    #|
    #|///|
    #|pub impl @d.DeriveFieldNames for Row with fn requested(_self) {}
  let out = generate_with_extension("row.mbt", src)
  // 顺序 = 源码中 impl 的书写顺序；键名来自各自的规则。
  @debug.debug_inspect(
    out.applied,
    content="[\"Row.to_csv\", \"Row.field_names\"]",
  )
  @debug.debug_inspect(
    contains_text(out.text, "impl @ext.ToCsv for Row"),
    content="true",
  )
  @debug.debug_inspect(
    contains_text(out.text, "impl @d.FieldNames for Row"),
    content="true",
  )
}

///|
test "没注册的标记 trait 会被明确报出来，而不是静默忽略" {
  let src =
    #|///|
    #|pub struct Row {
    #|  a : String
    #|}
    #|
    #|///|
    #|pub impl @ext.DeriveSomethingElse for Row with fn requested(_self) {}
  let out = generate_with_extension("row.mbt", src)
  @debug.debug_inspect(out.has_output, content="false")
  @debug.debug_inspect(out.diagnostics.length(), content="1")
  @debug.debug_inspect(
    contains_text(
      out.diagnostics[0],
      "未知的标记 trait `DeriveSomethingElse`",
    ),
    content="true",
  )
  @debug.debug_inspect(
    contains_text(out.diagnostics[0], "DeriveToCsv"),
    content="true",
  )
}

///|
test "只用自己的规则集：内置规则完全不出场" {
  let only_custom : Array[&@forge.DeriveRule] = [
    ToCsvRule::{ } as &@forge.DeriveRule,
  ]
  let src =
    #|///|
    #|pub struct Row {
    #|  a : String
    #|}
    #|
    #|///|
    #|pub impl @ext.DeriveToCsv for Row with fn requested(_self) {}
    #|
    #|///|
    #|pub impl @ext.DeriveFieldNames for Row with fn requested(_self) {}
  let out = @forge.generate(
    "row.mbt",
    src,
    only_custom,
    @forge.MOONFORGE_VERSION,
  )
  @debug.debug_inspect(out.applied, content="[\"Row.to_csv\"]")
  @debug.debug_inspect(out.diagnostics.length(), content="1")
  @debug.debug_inspect(
    contains_text(
      out.diagnostics[0],
      "未知的标记 trait `DeriveFieldNames`",
    ),
    content="true",
  )
}
