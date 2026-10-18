// 规则输入的**唯一契约**。
//
// 为什么要有这一层，而不是直接把 `TypeDef` 交给规则：
//
//   1. **规则不该依赖解析器的内部结构。** `TypeDef` 里还有 `variants` / `is_pub` /
//      `doc` / `kind` 这些与"按字段名展开"无关的字段；把它们交给规则，等于把解析器
//      的实现细节变成公开 API，以后想改 IR 就要改所有规则。
//   2. **parser 是可替换的前端，不是本项目的核心贡献。**（见
//      `docs/核心贡献边界.md`）只要能把任意前端的结果适配成 `DeriveInput`，
//      换掉整个 parser 也不影响任何一条规则。`codegen_wbtest.mbt` 里有一条测试
//      专门证明这一点：**不经过 parser，手工构造 `DeriveInput` 也能生成代码**。
//   3. **输入里必须带上"这次是被哪个请求触发的"。** 否则规则没法产出能指到
//      具体行号的诊断；而"为什么没生成"和"生成了什么"一样是产品的一部分。
//
// 契约内容（`DeriveInput::of` / `requested` 保证，`derive_input_wbtest.mbt` 钉住）：
//
//   * `type_name` 非空，且**不含包前缀**；
//   * `fields` 当且仅当该类型有具名字段时非空（`body == Record`）；
//   * 每个 `FieldDef::ty` 已归一化：已 trim、已去掉行尾注释、内部连续空白折叠成
//     单个空格、**不含尾随逗号**、**不含换行**；
//   * `FieldDef::attrs` 保持源码书写顺序；注解参数不做语义解释（由规则决定）；
//   * `request.marker` 是**不含包前缀**的标记 trait 名；`request.prefix` 是用户
//     书写时用的包前缀（`@derive` / `@d` / 空串），生成物原样复用；
//   * `request.line` 是那条 `impl` 在源文件里的行号（从 1 起）；`of()` 构造的
//     输入没有真实请求，`line` 为 0、`marker` 为空串。
//
// 这三份契约（身份 / 输入 / 输出）的完整说明在 `rule.mbt` 顶部。

///|
/// 触发这次生成的那条派生请求。
///
/// 规则拿到它，是为了**把话说准**：说明行里可以带上游标位置，
/// 诊断也不必由生成器在外面重新拼一遍。
pub(all) struct DeriveRequest {
  /// 用户书写标记 impl 时用的包前缀，例如 `@derive`；同包 trait 时为空串。
  prefix : String
  /// 标记 trait 名（不含包前缀），例如 `DeriveValidate`。
  marker : String
  /// 那条 `impl` 在源文件里的行号（从 1 起）；0 表示"不是真实请求"。
  line : Int
} derive(Debug, Eq)

///|
/// 一条规则的**全部输入**。规则只能看到这个类型，看不到 `TypeDef`。
///
/// 契约见本文件顶部；`fields` 里的 `FieldDef` 与 `Attr` 也属于契约的一部分。
pub(all) struct DeriveInput {
  /// 类型名，不含包前缀。
  type_name : String
  /// 字段体形态；只有 `Record` 才有具名字段。
  body : BodyKind
  /// 具名字段；非 `Record` 时为空数组。顺序 = 源码声明顺序。
  fields : Array[FieldDef]
  /// 触发本次生成的请求。
  request : DeriveRequest
} derive(Debug, Eq)

///|
/// 从一个类型定义构造输入，不带真实请求（`marker` 为空串、`line` 为 0）。
///
/// 用途：单元测试、以及"只想对某个类型试跑一条规则"的场景。
/// 真实生成走 `requested()` —— 它会把请求一起带进来。
pub fn DeriveInput::of(td : TypeDef) -> DeriveInput {
  {
    type_name: td.name,
    body: td.body,
    fields: td.fields,
    request: { prefix: "", marker: "", line: 0, },
  }
}

///|
/// 从类型定义 + 真实请求构造输入。生成器用的是这一个。
pub fn DeriveInput::requested(
  td : TypeDef,
  prefix : String,
  marker : String,
  line : Int,
) -> DeriveInput {
  {
    type_name: td.name,
    body: td.body,
    fields: td.fields,
    request: { prefix, marker, line, },
  }
}

///|
/// 该类型是否有具名字段 —— 也就是"按字段名展开"的规则能不能对它生效。
///
/// 规则的前置判断**只用这一个谓词**，不要自己去看 `body`：
/// 判断条件只有一处，将来新增字段体形态（例如 `newtype`）时不会被某条规则漏掉。
pub fn DeriveInput::has_named_fields(self : DeriveInput) -> Bool {
  match self.body {
    Record => true
    _ => false
  }
}

///|
/// 具名字段名，按声明顺序。没有具名字段时为空数组。
///
/// 这是规则里最常用的一步，单独给一个函数，省得每条规则各写一遍循环
/// —— 也顺手保证"顺序 = 声明顺序"这条约定只有一处实现。
pub fn DeriveInput::field_names(self : DeriveInput) -> Array[String] {
  let out : Array[String] = []
  for f in self.fields {
    out.push(f.name)
  }
  out
}

///|
/// 本次请求的标记 trait 名；`of()` 构造的输入返回空串。
pub fn DeriveInput::marker(self : DeriveInput) -> String {
  self.request.marker
}

///|
/// 本次请求在源文件里的行号；`of()` 构造的输入返回 0。
pub fn DeriveInput::line(self : DeriveInput) -> Int {
  self.request.line
}
