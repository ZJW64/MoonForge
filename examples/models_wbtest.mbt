// 端到端测试：直接使用 `models_derive_gen.mbt` 里**自动生成**的代码。
//
// 这些测试是“生成代码真的能用”的最直接证据：
// 它们引用的 `User::field_names` / `User::validate` / `User::diff` 等
// 在本仓库里**没有任何手写实现**，全部由 MoonForge 生成。

///|
test "生成的字段名列表与声明顺序一致" {
  @debug.debug_inspect(
    User::field_names(),
    content="[\"name\", \"age\", \"email\"]",
  )
  @debug.debug_inspect(
    Order::field_names(),
    content="[\"id\", \"amount_cents\", \"quantity\", \"note\"]",
  )
}

///|
test "生成的 validate：合法数据通过" {
  let u : User = { name: " Ada ", age: 36, email: "ada@example.com", }
  @debug.debug_inspect(u.validate(), content="Ok(())")
}

///|
test "生成的 validate：空字符串被拦住" {
  let u : User = { name: "", age: 36, email: "ada@example.com", }
  @debug.debug_inspect(
    u.validate(),
    content="Err(\"User.name must not be empty\")",
  )
}

///|
test "生成的 validate：上界被拦住（@max）" {
  let u : User = { name: "Ada", age: 200, email: "ada@example.com", }
  @debug.debug_inspect(u.validate(), content="Err(\"User.age must be <= 150\")")
}

///|
test "生成的 validate：下界被拦住（@min）" {
  let u : User = { name: "Ada", age: -1, email: "ada@example.com", }
  @debug.debug_inspect(u.validate(), content="Err(\"User.age must be >= 0\")")
}

///|
test "生成的 validate：@positive 生效" {
  let o : Order = { id: "O-1", amount_cents: 0, quantity: 1, note: "n", }
  @debug.debug_inspect(
    o.validate(),
    content="Err(\"Order.amount_cents must be positive\")",
  )
}

///|
test "边界：白名单之外的注解不会生成检查，因此负数也能通过" {
  // `quantity` 上写了 @nonempty 但类型是 Int —— 规则选择跳过而不是硬塞检查。
  // 这个测试把该边界固定下来：如果将来规则改成“对 Int 也判非零”，这里会失败并提醒改文档。
  let o : Order = { id: "O-2", amount_cents: 100, quantity: -5, note: "n", }
  @debug.debug_inspect(o.validate(), content="Ok(())")
}

///|
test "生成的 diff：只返回发生变化的字段名" {
  let a : User = { name: "Ada", age: 36, email: "ada@example.com", }
  let b : User = { name: "Ada", age: 37, email: "ada@example.com", }
  let c : User = { name: "Bob", age: 37, email: "bob@example.com", }
  @debug.debug_inspect(a.diff(b), content="[\"age\"]")
  @debug.debug_inspect(a.diff(a), content="[]")
  @debug.debug_inspect(a.diff(c), content="[\"name\", \"age\", \"email\"]")
}

///|
test "生成的 diff：字段顺序决定输出顺序" {
  let o1 : Order = { id: "O-1", amount_cents: 1, quantity: 1, note: "a", }
  let o2 : Order = { id: "O-1", amount_cents: 2, quantity: 1, note: "a", }
  @debug.debug_inspect(o1.diff(o2), content="[\"amount_cents\"]")
}

///|
test "零侵入：没有 @derive 标记的枚举不受影响（仅做构造与比较）" {
  let s : Status = Paid
  @debug.debug_inspect(s == Paid, content="true")
  @debug.debug_inspect(s == Shipped, content="false")
}

///|
test "生成的 to_pairs：只包含 String 字段，顺序与声明一致" {
  let u : User = { name: "Ada", age: 36, email: "ada@example.com", }
  @debug.debug_inspect(
    u.to_pairs(),
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
    a.to_pairs() == b.to_pairs(),
    content=(
      #|false
    ),
  )
  @debug.debug_inspect(
    a.to_pairs()[0] == ("name", "A") && a.to_pairs()[1] == ("email", "a@x"),
    content=(
      #|true
    ),
  )
}
