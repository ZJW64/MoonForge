// 输入契约（`DeriveInput`）的测试：把"规则能看到什么"钉死。
//
// 这些断言的意义不在于"函数能跑"，而在于**契约是承诺**：
// 第三方写规则时依赖的是这些不变量，一旦某条不变量被无意改掉，
// 别人的规则会在自己的仓库里悄悄生成错代码。所以每条都单独测。

///|
test "契约：of() 构造的输入不带真实请求" {
  let td = parse_source("struct A {\n  x : Int\n}")[0]
  let input = DeriveInput::of(td)
  @debug.debug_inspect(input.type_name, content="\"A\"")
  @debug.debug_inspect(input.marker(), content="\"\"")
  @debug.debug_inspect(input.line(), content="0")
}

///|
test "契约：requested() 原样带上请求的包前缀 / 标记名 / 行号" {
  let td = parse_source("struct A {\n  x : Int\n}")[0]
  let input = DeriveInput::requested(td, "@myalias", "DeriveXxx", 42)
  @debug.debug_inspect(input.type_name, content="\"A\"")
  @debug.debug_inspect(input.request.prefix, content="\"@myalias\"")
  @debug.debug_inspect(input.marker(), content="\"DeriveXxx\"")
  @debug.debug_inspect(input.line(), content="42")
}

///|
test "契约：字段类型已归一化 —— 无尾随逗号、无换行、空白折叠" {
  // 这三条是规则作者最容易踩的：如果 `ty` 带着尾随逗号或换行，
  // `f.ty == "String"` 这类白名单判断会静默失败，规则"看起来跑了"却没生成。
  let src =
    #|struct A {
    #|  a : String,
    #|  b : Map[
    #|    String,
    #|    Int
    #|  ],
    #|  c : Int?,
    #|}
  let input = DeriveInput::of(parse_source(src)[0])
  @debug.debug_inspect(input.fields[0].ty, content="\"String\"")
  @debug.debug_inspect(input.fields[1].ty, content="\"Map[ String, Int ]\"")
  @debug.debug_inspect(input.fields[2].ty, content="\"Int?\"")
  // 换行绝对不能进 IR：它会让生成物里出现半行代码。
  for f in input.fields {
    @debug.debug_inspect(f.ty.find("\n") is None, content="true")
    @debug.debug_inspect(f.ty.has_suffix(","), content="false")
  }
}

///|
test "契约：只有具名字段才有 fields；enum 与位置参数结构体都是空数组" {
  let record = DeriveInput::of(parse_source("struct R {\n  a : Int\n}")[0])
  @debug.debug_inspect(record.has_named_fields(), content="true")
  @debug.debug_inspect(record.fields.length(), content="1")

  let positional = DeriveInput::of(parse_source("struct P(Int, Int)")[0])
  @debug.debug_inspect(positional.has_named_fields(), content="false")
  @debug.debug_inspect(positional.fields.length(), content="0")

  let varianted = DeriveInput::of(parse_source("enum E {\n  A\n  B\n}")[0])
  @debug.debug_inspect(varianted.has_named_fields(), content="false")
  @debug.debug_inspect(varianted.fields.length(), content="0")

  let missing = DeriveInput::of(parse_source("struct M")[0])
  @debug.debug_inspect(missing.has_named_fields(), content="false")
  @debug.debug_inspect(missing.fields.length(), content="0")
}

///|
test "契约：field_names() 顺序 = 源码声明顺序" {
  let input = DeriveInput::of(
    parse_source("struct A {\n  z : Int\n  a : Int\n  m : Int\n}")[0],
  )
  @debug.debug_inspect(input.field_names(), content="[\"z\", \"a\", \"m\"]")
}

///|
test "契约：注解参数不做语义解释，原样保留（含空参数）" {
  let input = DeriveInput::of(
    parse_source(
      "struct A {\n  /// @min(0) @max(150)\n  /// @nonempty\n  a : Int\n}",
    )[0],
  )
  let f = input.fields[0]
  @debug.debug_inspect(f.attr_args("min"), content="[\"0\"]")
  @debug.debug_inspect(f.attr_args("max"), content="[\"150\"]")
  @debug.debug_inspect(f.has_attr("nonempty"), content="true")
  @debug.debug_inspect(f.has_attr("nosuch"), content="false")
}
