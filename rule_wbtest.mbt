// L1 单元测试：规则 SPI（trait）、注册表查找、名字校验。

///|
/// 测试桩规则：只回一段固定文本，用来验证注册表与查找逻辑。
/// 它的存在本身也说明一件事 —— 规则是一个**普通类型**，
/// 测试里随手定义一条，与内置规则走同一条路径。
struct StubRule {}

///|
impl DeriveRule for StubRule with fn head(_self) -> RuleHead {
  {
    key: "stub",
    marker: "DeriveStub",
    trait_name: "Stub",
    description: "测试桩",
  }
}

///|
impl DeriveRule for StubRule with fn generate(_self, _input) -> Fragment? {
  Some({ notes: [], impl_body: "fn stub(_self) -> Unit {\n}\n", })
}

///|
/// 永远不适用的规则：用来验证「不适用」是正常返回值而不是错误。
struct NeverRule {}

///|
impl DeriveRule for NeverRule with fn head(_self) -> RuleHead {
  {
    key: "never",
    marker: "DeriveNever",
    trait_name: "Never",
    description: "永不适用",
  }
}

///|
impl DeriveRule for NeverRule with fn generate(_self, _input) -> Fragment? {
  None
}

///|
fn sample_type() -> TypeDef {
  {
    name: "A",
    kind: TStruct,
    body: Record,
    is_pub: false,
    fields: [],
    variants: [],
    doc: "",
    attrs: [],
    line: 1,
  }
}

///|
test "规则名合法性校验" {
  @debug.debug_inspect(is_valid_rule_name("field_names"), content="true")
  @debug.debug_inspect(is_valid_rule_name("a1"), content="true")
  @debug.debug_inspect(is_valid_rule_name(""), content="false")
  @debug.debug_inspect(is_valid_rule_name("Bad"), content="false")
  @debug.debug_inspect(is_valid_rule_name("a-b"), content="false")
  @debug.debug_inspect(is_valid_rule_name("中文"), content="false")
}

///|
test "不合法规则名的原因文案只在非法时出现" {
  @debug.debug_inspect(
    invalid_rule_name_reason("ok_name") is None,
    content="true",
  )
  @debug.debug_inspect(
    invalid_rule_name_reason("Bad-Name") is Some(_),
    content="true",
  )
}

///|
test "注册表按键名与标记名双向可查" {
  let rs : Array[&DeriveRule] = [
    StubRule::{ } as &DeriveRule,
    NeverRule::{ } as &DeriveRule,
  ]
  @debug.debug_inspect(find_rule(rs, "stub") is Some(_), content="true")
  @debug.debug_inspect(find_rule(rs, "nope") is None, content="true")
  @debug.debug_inspect(
    find_rule_by_marker(rs, "DeriveStub") is Some(_),
    content="true",
  )
  @debug.debug_inspect(
    find_rule_by_marker(rs, "DeriveNope") is None,
    content="true",
  )
  @debug.debug_inspect(rule_keys(rs), content="[\"stub\", \"never\"]")
  @debug.debug_inspect(
    marker_names(rs),
    content="[\"DeriveStub\", \"DeriveNever\"]",
  )
}

///|
test "规则的四个身份字段通过 head() 暴露，并配有便捷读取函数" {
  let rs : Array[&DeriveRule] = [StubRule::{ } as &DeriveRule]
  match find_rule(rs, "stub") {
    Some(r) => {
      @debug.debug_inspect(key_of(r), content="\"stub\"")
      @debug.debug_inspect(marker_of(r), content="\"DeriveStub\"")
      @debug.debug_inspect(trait_name_of(r), content="\"Stub\"")
      @debug.debug_inspect(description_of(r), content="\"测试桩\"")
    }
    None => @debug.debug_inspect("unreachable", content="\"?\"")
  }
}

///|
test "generate 返回 None 表示不适用（不是错误）" {
  let rs : Array[&DeriveRule] = [NeverRule::{ } as &DeriveRule]
  match find_rule_by_marker(rs, "DeriveNever") {
    Some(r) =>
      @debug.debug_inspect(
        r.generate(DeriveInput::of(sample_type())) is None,
        content="true",
      )
    None => @debug.debug_inspect("unreachable", content="\"?\"")
  }
}

///|
/// 规则集合是 `Array[&DeriveRule]`：一个 trait object 数组。
/// 这条测试把它固定下来 —— 异构类型（两个不同的 struct）能放进同一个数组，
/// 遍历时只调 trait 方法，不关心背后是什么类型。这就是扩展点成立的前提。
test "异构规则集合可放进同一个数组并统一遍历" {
  let rs : Array[&DeriveRule] = [
    StubRule::{ } as &DeriveRule,
    NeverRule::{ } as &DeriveRule,
  ]
  let keys : Array[String] = []
  for r in rs {
    keys.push(key_of(r))
  }
  @debug.debug_inspect(rs.length(), content="2")
  @debug.debug_inspect(keys, content="[\"stub\", \"never\"]")
}

///|
test "Fragment 的两半各司其职：说明行与 impl 成员分开携带" {
  let f : Fragment = {
    notes: ["// note\n"],
    impl_body: "fn f(_self) -> Unit {\n}\n",
  }
  @debug.debug_inspect(f.notes.length(), content="1")
  @debug.debug_inspect(f.impl_body.has_prefix("fn f"), content="true")
}

///|
test "数值类型白名单" {
  @debug.debug_inspect(is_numeric_type("Int"), content="true")
  @debug.debug_inspect(is_numeric_type("Int64"), content="true")
  @debug.debug_inspect(is_numeric_type("Double"), content="true")
  @debug.debug_inspect(is_numeric_type("Int?"), content="false")
  @debug.debug_inspect(is_numeric_type("String"), content="false")
  @debug.debug_inspect(is_numeric_type("Array[Int]"), content="false")
}
