// L2 单元测试：语法分析（子集）。
//
// 注意：doc comment 里的 `@derive(...)` 自 0.3 起**不再是派生入口**，
// 但仍会被解析出来，用于给老用户输出迁移提示。相关断言调用的是
// `legacy_derive_rules()`；新的入口是 `parse(src).impls`（见文件末尾的用例）。
//
// 边界集中在四类：
//   1. 类型原文的切片是否精确（泛型、可选、带包名前缀）；
//   2. 注释归属是否严格“紧邻”；
//   3. 花括号深度为 0 的守卫是否真的把函数体排除在外；
//   4. 注解参数切分是否忽略嵌套括号内的逗号。

///|
fn names(tds : Array[TypeDef]) -> Array[String] {
  let out : Array[String] = []
  for td in tds {
    out.push(td.name)
  }
  out
}

///|
fn field_names_of(tds : Array[TypeDef], i : Int) -> Array[String] {
  let out : Array[String] = []
  for f in tds[i].fields {
    out.push(f.name + ":" + f.ty)
  }
  out
}

///|
test "解析：pub(all) struct 的可见性与字段" {
  let src =
    #|/// 用户
    #|/// @derive(validate)
    #|pub(all) struct User {
    #|  name : String
    #|  age : Int
    #|}
  let tds = parse_source(src)
  @debug.debug_inspect(
    names(tds),
    content=(
      #|["User"]
    ),
  )
  @debug.debug_inspect(
    tds[0].is_pub,
    content=(
      #|true
    ),
  )
  @debug.debug_inspect(
    tds[0].is_struct(),
    content=(
      #|true
    ),
  )
  @debug.debug_inspect(
    tds[0].doc,
    content=(
      #|"用户"
    ),
  )
  @debug.debug_inspect(
    tds[0].legacy_derive_rules(),
    content=(
      #|["validate"]
    ),
  )
  @debug.debug_inspect(
    field_names_of(tds, 0),
    content=(
      #|["name:String", "age:Int"]
    ),
  )
}

///|
test "解析：字段类型按源码原文切片（泛型 / 可选 / 包名 / 元组）" {
  let src =
    #|struct Holder {
    #|  m : Map[String, Array[Int]]
    #|  o : Int?
    #|  j : @json.Json
    #|  t : (Int, String)
    #|  f : (Int) -> String
    #|}
  @debug.debug_inspect(
    field_names_of(parse_source(src), 0),
    content=(
      #|[
      #|  "m:Map[String, Array[Int]]",
      #|  "o:Int?",
      #|  "j:@json.Json",
      #|  "t:(Int, String)",
      #|  "f:(Int) -> String",
      #|]
    ),
  )
}

///|
test "解析：老写法的 @derive 仍被识别（只用于迁移诊断，不参与生成）" {
  let src =
    #|/// @derive(zeta, alpha, beta)
    #|struct A { x : Int }
  @debug.debug_inspect(
    parse_source(src)[0].legacy_derive_rules(),
    content=(
      #|["zeta", "alpha", "beta"]
    ),
  )
}

///|
test "解析：字段注解（无参 + 有参 + 一行多个）" {
  let src =
    #|/// @derive(validate)
    #|struct A {
    #|  /// @nonempty
    #|  a : String
    #|  /// @min(0) @max(150)
    #|  b : Int
    #|  /// @range(1, 2)
    #|  c : Int
    #|}
  let td = parse_source(src)[0]
  @debug.debug_inspect(
    td.fields[0].has_attr("nonempty"),
    content=(
      #|true
    ),
  )
  @debug.debug_inspect(
    td.fields[1].attr_args("min"),
    content=(
      #|["0"]
    ),
  )
  @debug.debug_inspect(
    td.fields[1].attr_args("max"),
    content=(
      #|["150"]
    ),
  )
  @debug.debug_inspect(
    td.fields[1].attrs.length(),
    content=(
      #|2
    ),
  )
  @debug.debug_inspect(
    td.fields[2].attr_args("range"),
    content=(
      #|["1", "2"]
    ),
  )
  @debug.debug_inspect(
    td.fields[0].attrs.length(),
    content=(
      #|1
    ),
  )
}

///|
test "解析：注释必须紧邻，空行会切断归属" {
  let src =
    #|/// @derive(validate)
    #|
    #|struct A { x : Int }
  let td = parse_source(src)[0]
  @debug.debug_inspect(
    td.legacy_derive_rules().length(),
    content=(
      #|0
    ),
  )
  @debug.debug_inspect(
    td.doc,
    content=(
      #|""
    ),
  )
}

///|
test "解析：函数体、trait 体、test 块里的内容全部跳过" {
  let src =
    #|trait Show2 {
    #|  show(Self) -> String
    #|}
    #|
    #|fn helper() -> Int {
    #|  let s = { "a": 1 }
    #|  1
    #|}
    #|
    #|test "x" {
    #|  assert_true(true)
    #|}
    #|
    #|/// @derive(field_names)
    #|struct After { a : Int }
  let tds = parse_source(src)
  @debug.debug_inspect(
    names(tds),
    content=(
      #|["After"]
    ),
  )
  @debug.debug_inspect(
    tds[0].legacy_derive_rules(),
    content=(
      #|["field_names"]
    ),
  )
}

///|
test "解析：枚举构造器与变体" {
  let src =
    #|pub(all) enum Color {
    #|  Red
    #|  Green
    #|  Blue
    #|}
    #|
    #|struct S { v : Int }
  let tds = parse_source(src)
  @debug.debug_inspect(
    names(tds),
    content=(
      #|["Color", "S"]
    ),
  )
  @debug.debug_inspect(
    tds[0].is_enum(),
    content=(
      #|true
    ),
  )
  @debug.debug_inspect(
    tds[0].variants,
    content=(
      #|["Red", "Green", "Blue"]
    ),
  )
  @debug.debug_inspect(
    tds[1].is_enum(),
    content=(
      #|false
    ),
  )
}

///|
test "解析：泛型声明与 derive(...) 后缀不影响结果" {
  let src =
    #|/// @derive(field_names)
    #|pub struct Box[T] {
    #|  value : T
    #|} derive(Eq, Debug)
  let td = parse_source(src)[0]
  @debug.debug_inspect(
    td.name,
    content=(
      #|"Box"
    ),
  )
  @debug.debug_inspect(
    td.legacy_derive_rules(),
    content=(
      #|["field_names"]
    ),
  )
  @debug.debug_inspect(
    field_names_of(parse_source(src), 0),
    content=(
      #|["value:T"]
    ),
  )
}

///|
test "解析：语法不完整时不崩溃，尽力给出已有信息" {
  let src =
    #|struct Broken {
    #|  a : Int
  let tds = parse_source(src)
  @debug.debug_inspect(
    tds.length(),
    content=(
      #|1
    ),
  )
  @debug.debug_inspect(
    tds[0].fields.length(),
    content=(
      #|1
    ),
  )
}

///|
test "解析：没有类型定义时返回空数组" {
  @debug.debug_inspect(
    parse_source("fn main { println(\"hi\") }").length(),
    content=(
      #|0
    ),
  )
  @debug.debug_inspect(
    parse_source("").length(),
    content=(
      #|0
    ),
  )
}

///|
test "解析：注解不会被误判（邮箱、正文里的 @）" {
  let src =
    #|/// 联系 a@b.com 获取帮助
    #|/// @derive(validate)
    #|struct A { x : Int }
  let td = parse_source(src)[0]
  @debug.debug_inspect(
    td.attrs.length(),
    content=(
      #|1
    ),
  )
  @debug.debug_inspect(
    td.legacy_derive_rules(),
    content=(
      #|["validate"]
    ),
  )
  @debug.debug_inspect(
    td.doc,
    content=(
      #|"联系 a@b.com 获取帮助"
    ),
  )
}

///|
test "解析：位置参数结构体不再吞掉下一个声明的字段体" {
  // 修复前：`struct Point(Int, Int)` 会让解析器一路向后找 `{`，结果把
  // 后面 Holder 的字段当成 Point 的字段，同时 Holder 被静默丢弃 ——
  // 生成出来的 Point::field_names 返回 Holder 的字段名，diff 还会引用
  // 根本不存在的字段，直接编译不过。
  let src =
    #|/// @derive(field_names)
    #|pub struct Point(Int, Int)
    #|
    #|/// @derive(field_names)
    #|struct Holder {
    #|  a : Int
    #|  b : String
    #|}
  let tds = parse_source(src)
  @debug.debug_inspect(
    names(tds),
    content=(
      #|["Point", "Holder"]
    ),
  )
  @debug.debug_inspect(
    tds[0].body,
    content=(
      #|Positional
    ),
  )
  @debug.debug_inspect(
    tds[0].fields.length(),
    content=(
      #|0
    ),
  )
  @debug.debug_inspect(
    tds[0].has_named_fields(),
    content=(
      #|false
    ),
  )
  @debug.debug_inspect(
    field_names_of(tds, 1),
    content=(
      #|["a:Int", "b:String"]
    ),
  )
  @debug.debug_inspect(
    tds[1].has_named_fields(),
    content=(
      #|true
    ),
  )
}

///|
test "解析：带泛型参数的位置参数结构体" {
  let src =
    #|/// @derive(field_names)
    #|struct Pair[T](T, T)
    #|
    #|struct After { k : String }
  let tds = parse_source(src)
  @debug.debug_inspect(
    names(tds),
    content=(
      #|["Pair", "After"]
    ),
  )
  @debug.debug_inspect(
    tds[0].body,
    content=(
      #|Positional
    ),
  )
  @debug.debug_inspect(
    field_names_of(tds, 1),
    content=(
      #|["k:String"]
    ),
  )
}

///|
test "解析：没有字段体的声明不越界借用下一个声明的花括号" {
  let src =
    #|/// @derive(field_names)
    #|struct Opaque
    #|
    #|struct Real {
    #|  a : Int
    #|}
  let tds = parse_source(src)
  @debug.debug_inspect(
    names(tds),
    content=(
      #|["Opaque", "Real"]
    ),
  )
  @debug.debug_inspect(
    tds[0].body,
    content=(
      #|Missing
    ),
  )
  @debug.debug_inspect(
    field_names_of(tds, 1),
    content=(
      #|["a:Int"]
    ),
  )
}

///|
test "解析：花括号写在下一行仍然被接受" {
  let src =
    #|/// @derive(field_names)
    #|struct Brace
    #|{
    #|  k : String
    #|}
    #|
    #|struct After { n : Int }
  let tds = parse_source(src)
  @debug.debug_inspect(
    names(tds),
    content=(
      #|["Brace", "After"]
    ),
  )
  @debug.debug_inspect(
    tds[0].body,
    content=(
      #|Record
    ),
  )
  @debug.debug_inspect(
    field_names_of(tds, 0),
    content=(
      #|["k:String"]
    ),
  )
}

///|
test "解析：尾随逗号不进类型原文（否则白名单判断会失效）" {
  let src =
    #|/// @derive(validate)
    #|struct A {
    #|  /// @nonempty
    #|  a : String,
    #|  /// @min(0)
    #|  b : Int,
    #|}
  let tds = parse_source(src)
  @debug.debug_inspect(
    field_names_of(tds, 0),
    content=(
      #|["a:String", "b:Int"]
    ),
  )
  // 类型原文干净了，白名单才能命中 —— 这条断言正是修复的动机
  @debug.debug_inspect(
    tds[0].fields[0].ty == "String" && tds[0].fields[1].ty == "Int",
    content=(
      #|true
    ),
  )
}

///|
test "解析：元组/泛型里的逗号属于类型本身，要保留" {
  let src =
    #|struct A {
    #|  t : (Int, String),
    #|  m : Map[String, Int],
    #|}
  @debug.debug_inspect(
    field_names_of(parse_source(src), 0),
    content=(
      #|["t:(Int, String)", "m:Map[String, Int]"]
    ),
  )
}

///|
test "解析：跨行书写的字段类型折叠掉内部空白" {
  let src =
    #|struct A {
    #|  m : Map[
    #|    String,
    #|    Int
    #|  ]
    #|  n : Int
    #|}
  let tds = parse_source(src)
  // 跨行与单行必须是同一个类型字符串，否则规则里的类型比较会受排版影响
  @debug.debug_inspect(
    tds[0].fields[0].ty,
    content=(
      #|"Map[ String, Int ]"
    ),
  )
  @debug.debug_inspect(
    field_names_of(tds, 0),
    content=(
      #|["m:Map[ String, Int ]", "n:Int"]
    ),
  )
}

///|
test "解析：带载荷的枚举只收集构造器名" {
  // 修复前会把载荷里的类型名一并当成变体：
  // ["A", "Int", "B", "String", "Int"]
  let src =
    #|pub enum Payload {
    #|  A(Int)
    #|  B(String, Int)
    #|  C
    #|}
  let td = parse_source(src)[0]
  @debug.debug_inspect(
    td.variants,
    content=(
      #|["A", "B", "C"]
    ),
  )
  @debug.debug_inspect(
    td.is_enum(),
    content=(
      #|true
    ),
  )
  @debug.debug_inspect(
    td.body,
    content=(
      #|Variants
    ),
  )
}

///|
test "解析：单行结构体的字段不继承类型上的注解" {
  // 修复前字段与声明在同一行，`take_docs` 只看"紧邻声明行的上一行"，
  // 于是类型上的 `@nonempty` / `@derive(...)` 会被复制到字段 `x` 上。
  // 后果不只是 explain 输出变脏：把类型注解当成字段注解，会生成用户
  // 根本没请求的校验代码。
  let src =
    #|/// @nonempty
    #|/// @derive(validate)
    #|struct A { x : String }
  let td = parse_source(src)[0]
  @debug.debug_inspect(
    td.legacy_derive_rules(),
    content=(
      #|["validate"]
    ),
  )
  @debug.debug_inspect(
    td.fields[0].attrs.length(),
    content=(
      #|0
    ),
  )
  @debug.debug_inspect(
    td.fields[0].has_attr("nonempty"),
    content=(
      #|false
    ),
  )
  @debug.debug_inspect(
    td.fields[0].doc,
    content=(
      #|""
    ),
  )
}

///|
test "解析：多行结构体的字段注解照常归属（修复没有误伤正常写法）" {
  let src =
    #|/// 类型注释
    #|/// @derive(validate)
    #|struct A {
    #|  /// 字段注释
    #|  /// @nonempty
    #|  a : String
    #|}
  let td = parse_source(src)[0]
  @debug.debug_inspect(
    td.doc,
    content=(
      #|"类型注释"
    ),
  )
  @debug.debug_inspect(
    td.fields[0].doc,
    content=(
      #|"字段注释"
    ),
  )
  @debug.debug_inspect(
    td.fields[0].has_attr("nonempty"),
    content=(
      #|true
    ),
  )
  @debug.debug_inspect(
    td.fields[0].attrs.length(),
    content=(
      #|1
    ),
  )
}

///|
test "解析：花括号写在下一行时，字段注解仍然归属正确" {
  let src =
    #|/// @derive(validate)
    #|struct A
    #|{
    #|  /// @nonempty
    #|  a : String
    #|}
  let td = parse_source(src)[0]
  @debug.debug_inspect(
    td.fields[0].has_attr("nonempty"),
    content=(
      #|true
    ),
  )
  @debug.debug_inspect(
    td.fields[0].attrs.length(),
    content=(
      #|1
    ),
  )
}

// ---------------------------------------------------------------------------
// 0.3 新入口：`impl <标记 trait> for <类型>` 的解析
// ---------------------------------------------------------------------------

///|
/// 把一条派生请求压成 "prefix|marker|target" 便于断言。
fn impl_shape(impls : Array[ImplDecl], i : Int) -> String {
  impls[i].prefix + "|" + impls[i].marker + "|" + impls[i].target
}

///|
test "入口解析：带包前缀的标记 impl" {
  let src =
    #|pub impl @derive.DeriveFieldNames for User with fn requested(_self) {}
  let p = parse(src)
  @debug.debug_inspect(p.types.length(), content="0")
  @debug.debug_inspect(p.impls.length(), content="1")
  @debug.debug_inspect(
    impl_shape(p.impls, 0),
    content="\"@derive|DeriveFieldNames|User\"",
  )
}

///|
test "入口解析：同包 trait（没有 @ 前缀）" {
  let p = parse("impl DeriveFieldNames for User with fn requested(_self) {}")
  @debug.debug_inspect(p.impls.length(), content="1")
  @debug.debug_inspect(
    impl_shape(p.impls, 0),
    content="\"|DeriveFieldNames|User\"",
  )
}

///|
test "入口解析：多级包路径只把最后一段当标记名" {
  let p = parse("impl @a.b.DeriveX for T with fn requested(_self) {}")
  @debug.debug_inspect(impl_shape(p.impls, 0), content="\"@a.b|DeriveX|T\"")
}

///|
test "入口解析：泛型目标类型只取类型名" {
  let src =
    #|pub impl @derive.DeriveFieldNames for Box[T] with fn requested(_self) {}
  let p = parse(src)
  @debug.debug_inspect(
    impl_shape(p.impls, 0),
    content="\"@derive|DeriveFieldNames|Box\"",
  )
}

///|
test "入口解析：固有 impl（impl Foo with ...）不是派生请求" {
  let src =
    #|pub struct User {
    #|  id : Int
    #|}
    #|
    #|pub impl User with fn id_of(self) -> Int {
    #|  self.id
    #|}
  let p = parse(src)
  @debug.debug_inspect(p.types.length(), content="1")
  @debug.debug_inspect(p.impls.length(), content="0")
}

///|
test "入口解析：impl 体内的花括号与同名关键字不会污染扫描" {
  // 花括号深度守卫必须覆盖 impl 体：里面的 `{` `}` 不能让解析器
  // 在错误的位置认 `struct`，也不能让后面的声明被吞掉。
  let src =
    #|pub impl @derive.DeriveFieldNames for User with fn requested(_self) {
    #|  let s = { "a": 1 }
    #|  struct Fake { y : Int }
    #|}
    #|
    #|struct Later {
    #|  x : Int
    #|}
  let p = parse(src)
  @debug.debug_inspect(p.impls.length(), content="1")
  @debug.debug_inspect(names(p.types), content="[\"Later\"]")
}

///|
test "入口解析：多条 impl 保持书写顺序，类型与 impl 可混排" {
  let src =
    #|///|
    #|pub struct User {
    #|  id : Int
    #|}
    #|
    #|///|
    #|pub impl @derive.DeriveValidate for User with fn requested(_self) {}
    #|
    #|///|
    #|pub impl @derive.DeriveDiff for User with fn requested(_self) {}
    #|
    #|///|
    #|pub struct Order {
    #|  id : String
    #|}
    #|
    #|///|
    #|pub impl @derive.DeriveFieldNames for Order with fn requested(_self) {}
  let p = parse(src)
  @debug.debug_inspect(names(p.types), content="[\"User\", \"Order\"]")
  @debug.debug_inspect(p.impls.length(), content="3")
  @debug.debug_inspect(
    [impl_shape(p.impls, 0), impl_shape(p.impls, 1), impl_shape(p.impls, 2)],
    content=(
      #|[
      #|  "@derive|DeriveValidate|User",
      #|  "@derive|DeriveDiff|User",
      #|  "@derive|DeriveFieldNames|Order",
      #|]
    ),
  )
}

///|
test "入口解析：只有 impl 没有类型时，类型数组为空而请求仍被记录" {
  let p = parse(
    "impl @derive.DeriveFieldNames for Ghost with fn requested(_self) {}",
  )
  @debug.debug_inspect(p.types.length(), content="0")
  @debug.debug_inspect(
    impl_shape(p.impls, 0),
    content="\"@derive|DeriveFieldNames|Ghost\"",
  )
}

///|
test "入口解析：行号被记录（诊断要指到具体那一行）" {
  let src =
    #|///|
    #|pub struct User {
    #|  id : Int
    #|}
    #|
    #|///|
    #|pub impl @derive.DeriveFieldNames for User with fn requested(_self) {}
  let p = parse(src)
  @debug.debug_inspect(p.impls[0].line, content="7")
}
