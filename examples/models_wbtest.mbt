// 端到端测试：直接使用 `models_derive_gen.mbt` 里**自动生成**的代码。
//
// 这些测试是“生成代码真的能用”的最直接证据：它们调用的
// `@derive.FieldNames::field_names` / `Validate::validate` / `Diff::diff` /
// `ToPairs::to_pairs` 在本仓库里**没有任何手写实现**，全部由 MoonForge 生成。
//
// 调用一律写成 `Trait::method(x)` 的显式形式（UFCS）。方法语法
// `x.field_names()` 需要 `extend` 声明，MoonBit 当前会给出弃用提示；
// 显式形式在哪都成立，也更清楚地表明"这是 trait 方法，来自派生"。

///|
test "生成的字段名列表与声明顺序一致" {
  let u : User = { name: "Ada", age: 36, email: "ada@example.com", }
  let o : Order = { id: "O-1", amount_cents: 1, quantity: 1, note: "n", }
  @debug.debug_inspect(
    @derive.FieldNames::field_names(u),
    content="[\"name\", \"age\", \"email\"]",
  )
  @debug.debug_inspect(
    @derive.FieldNames::field_names(o),
    content="[\"id\", \"amount_cents\", \"quantity\", \"note\"]",
  )
}

///|
test "生成的 validate：合法数据通过" {
  let u : User = { name: "Ada", age: 36, email: "ada@example.com", }
  @debug.debug_inspect(@derive.Validate::validate(u), content="Ok(())")
}

///|
test "生成的 validate：空字符串被拦住" {
  let u : User = { name: "", age: 36, email: "ada@example.com", }
  @debug.debug_inspect(
    @derive.Validate::validate(u),
    content="Err(\"User.name must not be empty\")",
  )
}

///|
test "生成的 validate：上界被拦住（@max）" {
  let u : User = { name: "Ada", age: 200, email: "ada@example.com", }
  @debug.debug_inspect(
    @derive.Validate::validate(u),
    content="Err(\"User.age must be <= 150\")",
  )
}

///|
test "生成的 validate：下界被拦住（@min）" {
  let u : User = { name: "Ada", age: -1, email: "ada@example.com", }
  @debug.debug_inspect(
    @derive.Validate::validate(u),
    content="Err(\"User.age must be >= 0\")",
  )
}

///|
test "生成的 validate：@positive 生效" {
  let o : Order = { id: "O-1", amount_cents: 0, quantity: 1, note: "n", }
  @debug.debug_inspect(
    @derive.Validate::validate(o),
    content="Err(\"Order.amount_cents must be positive\")",
  )
}

///|
test "边界：白名单之外的注解不会生成检查，因此负数也能通过" {
  // `quantity` 上写了 @nonempty 但类型是 Int —— 规则选择跳过而不是硬塞检查。
  // 这个测试把该边界固定下来：如果将来规则改成“对 Int 也判非零”，这里会失败并提醒改文档。
  let o : Order = { id: "O-2", amount_cents: 100, quantity: -5, note: "n", }
  @debug.debug_inspect(@derive.Validate::validate(o), content="Ok(())")
}

///|
test "生成的 diff：只返回发生变化的字段名" {
  let a : User = { name: "Ada", age: 36, email: "ada@example.com", }
  let b : User = { name: "Ada", age: 37, email: "ada@example.com", }
  let c : User = { name: "Bob", age: 37, email: "bob@example.com", }
  @debug.debug_inspect(@derive.Diff::diff(a, b), content="[\"age\"]")
  @debug.debug_inspect(@derive.Diff::diff(a, a), content="[]")
  @debug.debug_inspect(
    @derive.Diff::diff(a, c),
    content="[\"name\", \"age\", \"email\"]",
  )
}

///|
test "生成的 diff：字段顺序决定输出顺序" {
  let o1 : Order = { id: "O-1", amount_cents: 1, quantity: 1, note: "a", }
  let o2 : Order = { id: "O-1", amount_cents: 2, quantity: 1, note: "a", }
  @debug.debug_inspect(@derive.Diff::diff(o1, o2), content="[\"amount_cents\"]")
}

///|
test "零侵入：没有派生标记的枚举不受影响（仅做构造与比较）" {
  let s : Status = Paid
  @debug.debug_inspect(s == Paid, content="true")
  @debug.debug_inspect(s == Shipped, content="false")
}

///|
test "生成的 to_pairs：只包含 String 字段，顺序与声明一致" {
  let u : User = { name: "Ada", age: 36, email: "ada@example.com", }
  @debug.debug_inspect(
    @derive.ToPairs::to_pairs(u),
    content=(
      #|[("name", "Ada"), ("email", "ada@example.com")]
    ),
  )
}

///|
test "生成的 to_pairs：值跟着数据走（不是把字段名返回两遍）" {
  let a : User = { name: "A", age: 1, email: "a@x", }
  let b : User = { name: "B", age: 2, email: "b@x", }
  @debug.debug_inspect(
    @derive.ToPairs::to_pairs(a) == @derive.ToPairs::to_pairs(b),
    content=(
      #|false
    ),
  )
  let pa = @derive.ToPairs::to_pairs(a)
  @debug.debug_inspect(
    pa[0] == ("name", "A") && pa[1] == ("email", "a@x"),
    content=(
      #|true
    ),
  )
}

///|
test "派生内容与源文件的请求一一对应：User 四项、Order 三项" {
  // 这条断言把「写了什么就生成什么」钉住：改动注册表或标记写法时，
  // 若数量对不上，这里会先失败。
  let u : User = { name: "A", age: 1, email: "a@x", }
  let o : Order = { id: "O", amount_cents: 1, quantity: 1, note: "n", }
  let u_validation : Result[Unit, String] = @derive.Validate::validate(u)
  let u_diff : Array[String] = @derive.Diff::diff(u, u)
  let u_names : Array[String] = @derive.FieldNames::field_names(u)
  let u_pairs : Array[(String, String)] = @derive.ToPairs::to_pairs(u)
  let o_validation : Result[Unit, String] = @derive.Validate::validate(o)
  let o_diff : Array[String] = @derive.Diff::diff(o, o)
  let o_names : Array[String] = @derive.FieldNames::field_names(o)
  let user_ok = u_validation == Ok(()) &&
    u_diff.length() == 0 &&
    u_names.length() == 3 &&
    u_pairs.length() == 2
  let order_ok = o_validation == Ok(()) &&
    o_diff.length() == 0 &&
    o_names.length() == 4
  @debug.debug_inspect(user_ok && order_ok, content="true")
}
