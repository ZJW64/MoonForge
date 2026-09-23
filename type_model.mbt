// 类型模型（IR）：解析结果的唯一表示。
//
// 所有规则都只依赖这一层，因此“新增一条规则”不需要碰词法/语法代码。

///|
/// 一条注解，例如 `@nonempty`、`@min(0)`、`@derive(validate, diff)`。
///
/// 参数保留为字符串，不在这里做语义解释 —— 语义由具体规则决定，
/// 这样新增规则时无需修改本文件（开放-封闭）。
pub(all) struct Attr {
  name : String
  args : Array[String]
} derive(Debug, Eq)

///|
/// 结构体字段。
pub(all) struct FieldDef {
  name : String
  /// 字段类型的**源码原文**（如 `String`、`Array[Int]`、`Int?`）。
  /// 框架不对其做语义分析，由规则按需判断。
  ty : String
  /// 除注解行以外的文档注释正文，多个自然行以 `\n` 连接。
  doc : String
  attrs : Array[Attr]
  line : Int
} derive(Debug, Eq)

///|
/// 类型种类。本期规则只对 `TStruct` 生效，`TEnum` 会被规则显式跳过。
pub(all) enum TypeKind {
  TStruct
  TEnum
} derive(Debug, Eq)

///|
/// 声明的“字段体”形态 —— 决定这个类型有没有**具名字段**。
///
/// 分开描述是必要的：`struct Point(Int, Int)` 与 `struct Point { x : Int }`
/// 在 `TypeKind` 上都算 `TStruct`，但前者没有字段名，`field_names` / `diff` /
/// `validate` 这些按名字展开的规则对它完全没有意义。如果只看 `TypeKind`，
/// 生成器就会对位置参数结构体生成出一个空字段列表 —— 语法上说得通、
/// 语义上完全错误，而且编译器不会报错。
pub(all) enum BodyKind {
  /// `struct T { ... }`：有具名字段。四条内置规则只对这类类型生效。
  Record
  /// `struct T(T1, T2)`：位置参数（元组）结构体，没有字段名。
  Positional
  /// `enum T { ... }`：变体在 `variants` 里。
  Variants
  /// 名字之后既没有 `(` 也没有 `{`（源码不完整，或不是本项目认识的写法）。
  Missing
} derive(Debug, Eq)

///|
/// 一个顶层类型定义。
pub(all) struct TypeDef {
  name : String
  kind : TypeKind
  /// 字段体形态；只有 `Record` 才有具名字段。
  body : BodyKind
  is_pub : Bool
  /// 具名字段；非 `Record` 时为空。
  fields : Array[FieldDef]
  /// 枚举构造器名；结构体时为空。
  variants : Array[String]
  doc : String
  /// 类型级注解，`@derive(...)` 就在这里。
  attrs : Array[Attr]
  line : Int
} derive(Debug, Eq)

///|
pub fn TypeDef::is_struct(self : TypeDef) -> Bool {
  match self.kind {
    TStruct => true
    TEnum => false
  }
}

///|
pub fn TypeDef::is_enum(self : TypeDef) -> Bool {
  match self.kind {
    TEnum => true
    TStruct => false
  }
}

///|
/// 该类型是否有具名字段 —— 也就是“按字段名展开”的规则能不能对它生效。
///
/// 所有内置规则都应该用它而不是 `is_enum()` 做前置判断：判断条件只有一处，
/// 新增的字段体形态（例如将来的 `newtype`）不会被某条规则漏掉。
pub fn TypeDef::has_named_fields(self : TypeDef) -> Bool {
  match self.kind {
    TStruct => self.body == Record
    TEnum => false
  }
}

///|
/// 类型在 `explain` 里的展示标签。
///
/// 位置参数结构体与"没有字段体"的声明会带上括号补充说明：它们在 `explain`
/// 输出里后面不会跟任何 `field` 行，不解释一下会显得像解析失败。
pub fn TypeDef::body_label(self : TypeDef) -> String {
  match self.kind {
    TEnum => "enum"
    TStruct =>
      match self.body {
        Positional => "struct(位置参数)"
        Missing => "struct(无字段体)"
        _ => "struct"
      }
  }
}

///|
/// 取该类型声明的派生规则名，按**书写顺序**返回（顺序决定输出顺序，保持字节稳定）。
pub fn TypeDef::derive_rules(self : TypeDef) -> Array[String] {
  let out : Array[String] = []
  for a in self.attrs {
    if a.name == "derive" {
      for x in a.args {
        out.push(x)
      }
    }
  }
  out
}

///|
/// 取字段上某个注解的所有参数；注解不存在时返回空数组。
pub fn FieldDef::attr_args(self : FieldDef, name : String) -> Array[String] {
  let out : Array[String] = []
  for a in self.attrs {
    if a.name == name {
      for x in a.args {
        out.push(x)
      }
    }
  }
  out
}

///|
/// 字段是否带某个无参注解。
pub fn FieldDef::has_attr(self : FieldDef, name : String) -> Bool {
  let mut found = false
  for a in self.attrs {
    if a.name == name {
      found = true
    }
  }
  found
}

///|
/// 判断字段类型原文是否为内建数值类型。
///
/// 这里刻意用白名单而不是“猜类型”：白名单之外一律不生成比较代码，
/// 宁可少生成，也不生成编译不过的代码（生成物要能过 `moon check`）。
pub fn is_numeric_type(ty : String) -> Bool {
  let t = ty.trim().to_owned()
  t == "Int" ||
  t == "Int64" ||
  t == "Int16" ||
  t == "UInt" ||
  t == "UInt64" ||
  t == "UInt16" ||
  t == "Double" ||
  t == "Float"
}
