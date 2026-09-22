// L2 单元测试：语法分析（子集）。
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
  @debug.debug_inspect(names(tds), content=(
    #|["User"]
  ))
  @debug.debug_inspect(tds[0].is_pub, content=(
    #|true
  ))
  @debug.debug_inspect(tds[0].is_struct(), content=(
    #|true
  ))
  @debug.debug_inspect(tds[0].doc, content=(
    #|"用户"
  ))
  @debug.debug_inspect(tds[0].derive_rules(), content=(
    #|["validate"]
  ))
  @debug.debug_inspect(field_names_of(tds, 0), content=(
    #|["name:String", "age:Int"]
  ))
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
  @debug.debug_inspect(field_names_of(parse_source(src), 0), content=(
    #|[
    #|  "m:Map[String, Array[Int]]",
    #|  "o:Int?",
    #|  "j:@json.Json",
    #|  "t:(Int, String)",
    #|  "f:(Int) -> String",
    #|]
  ))
}

///|
test "解析：@derive 保持书写顺序，决定输出顺序" {
  let src =
    #|/// @derive(zeta, alpha, beta)
    #|struct A { x : Int }
  @debug.debug_inspect(parse_source(src)[0].derive_rules(), content=(
    #|["zeta", "alpha", "beta"]
  ))
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
  @debug.debug_inspect(td.fields[0].has_attr("nonempty"), content=(
    #|true
  ))
  @debug.debug_inspect(td.fields[1].attr_args("min"), content=(
    #|["0"]
  ))
  @debug.debug_inspect(td.fields[1].attr_args("max"), content=(
    #|["150"]
  ))
  @debug.debug_inspect(td.fields[1].attrs.length(), content=(
    #|2
  ))
  @debug.debug_inspect(td.fields[2].attr_args("range"), content=(
    #|["1", "2"]
  ))
  @debug.debug_inspect(td.fields[0].attrs.length(), content=(
    #|1
  ))
}

///|
test "解析：注释必须紧邻，空行会切断归属" {
  let src =
    #|/// @derive(validate)
    #|
    #|struct A { x : Int }
  let td = parse_source(src)[0]
  @debug.debug_inspect(td.derive_rules().length(), content=(
    #|0
  ))
  @debug.debug_inspect(td.doc, content=(
    #|""
  ))
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
  @debug.debug_inspect(names(tds), content=(
    #|["After"]
  ))
  @debug.debug_inspect(tds[0].derive_rules(), content=(
    #|["field_names"]
  ))
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
  @debug.debug_inspect(names(tds), content=(
    #|["Color", "S"]
  ))
  @debug.debug_inspect(tds[0].is_enum(), content=(
    #|true
  ))
  @debug.debug_inspect(tds[0].variants, content=(
    #|["Red", "Green", "Blue"]
  ))
  @debug.debug_inspect(tds[1].is_enum(), content=(
    #|false
  ))
}

///|
test "解析：泛型声明与 derive(...) 后缀不影响结果" {
  let src =
    #|/// @derive(field_names)
    #|pub struct Box[T] {
    #|  value : T
    #|} derive(Eq, Debug)
  let td = parse_source(src)[0]
  @debug.debug_inspect(td.name, content=(
    #|"Box"
  ))
  @debug.debug_inspect(td.derive_rules(), content=(
    #|["field_names"]
  ))
  @debug.debug_inspect(field_names_of(parse_source(src), 0), content=(
    #|["value:T"]
  ))
}

///|
test "解析：语法不完整时不崩溃，尽力给出已有信息" {
  let src =
    #|struct Broken {
    #|  a : Int
  let tds = parse_source(src)
  @debug.debug_inspect(tds.length(), content=(
    #|1
  ))
  @debug.debug_inspect(tds[0].fields.length(), content=(
    #|1
  ))
}

///|
test "解析：没有类型定义时返回空数组" {
  @debug.debug_inspect(parse_source("fn main { println(\"hi\") }").length(), content=(
    #|0
  ))
  @debug.debug_inspect(parse_source("").length(), content=(
    #|0
  ))
}

///|
test "解析：注解不会被误判（邮箱、正文里的 @）" {
  let src =
    #|/// 联系 a@b.com 获取帮助
    #|/// @derive(validate)
    #|struct A { x : Int }
  let td = parse_source(src)[0]
  @debug.debug_inspect(td.attrs.length(), content=(
    #|1
  ))
  @debug.debug_inspect(td.derive_rules(), content=(
    #|["validate"]
  ))
  @debug.debug_inspect(td.doc, content=(
    #|"联系 a@b.com 获取帮助"
  ))
}
