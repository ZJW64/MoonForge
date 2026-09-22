// L1 单元测试：规则接口与注册表。

///|
test "规则名合法性校验" {
  @debug.debug_inspect(is_valid_rule_name("field_names"), content=(
    #|true
  ))
  @debug.debug_inspect(is_valid_rule_name("a1"), content=(
    #|true
  ))
  @debug.debug_inspect(is_valid_rule_name(""), content=(
    #|false
  ))
  @debug.debug_inspect(is_valid_rule_name("Bad"), content=(
    #|false
  ))
  @debug.debug_inspect(is_valid_rule_name("a-b"), content=(
    #|false
  ))
  @debug.debug_inspect(is_valid_rule_name("中文"), content=(
    #|false
  ))
}

///|
test "按名字查规则：命中与未命中" {
  let r : Rule = {
    name: "x",
    description: "d",
    gen: fn(_td : TypeDef) -> String? { None },
  }
  let rs = [r]
  @debug.debug_inspect(find_rule(rs, "x") is Some(_), content=(
    #|true
  ))
  @debug.debug_inspect(find_rule(rs, "y") is None, content=(
    #|true
  ))
  @debug.debug_inspect(rule_names(rs), content=(
    #|["x"]
  ))
}

///|
test "Rule::apply 会转发到 gen，并把 None 原样返回" {
  let r : Rule = {
    name: "always_none",
    description: "",
    gen: fn(_td : TypeDef) -> String? { None },
  }
  let td : TypeDef = {
    name: "A",
    kind: TStruct,
    is_pub: false,
    fields: [],
    variants: [],
    doc: "",
    attrs: [],
    line: 1,
  }
  @debug.debug_inspect(r.apply(td) is None, content=(
    #|true
  ))
}

///|
test "数值类型白名单" {
  @debug.debug_inspect(is_numeric_type("Int"), content=(
    #|true
  ))
  @debug.debug_inspect(is_numeric_type("Int64"), content=(
    #|true
  ))
  @debug.debug_inspect(is_numeric_type("Double"), content=(
    #|true
  ))
  @debug.debug_inspect(is_numeric_type("Int?"), content=(
    #|false
  ))
  @debug.debug_inspect(is_numeric_type("String"), content=(
    #|false
  ))
  @debug.debug_inspect(is_numeric_type("Array[Int]"), content=(
    #|false
  ))
}
