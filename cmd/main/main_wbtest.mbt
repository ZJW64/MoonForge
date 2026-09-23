// L8 单元测试：CLI 的参数归一化与路径处理。
//
// 这些函数是 `explain` / `gen` / `check` 三个子命令共用的地基：
// 参数归一化错了会把宿主注入的 argv 前缀当成子命令，路径拆分错了会把生成物写到错误目录。
// 它们都是纯函数，因此可以脱离文件系统直接断言。

///|
test "is_command 只认已知子命令（用于削掉宿主 argv 前缀）" {
  @debug.debug_inspect(
    is_command("gen"),
    content=(
      #|true
    ),
  )
  @debug.debug_inspect(
    is_command("explain"),
    content=(
      #|true
    ),
  )
  @debug.debug_inspect(
    is_command("check"),
    content=(
      #|true
    ),
  )
  @debug.debug_inspect(
    is_command("--help"),
    content=(
      #|true
    ),
  )
  // 宿主注入的前缀不能被误认成子命令
  @debug.debug_inspect(
    is_command("node"),
    content=(
      #|false
    ),
  )
  @debug.debug_inspect(
    is_command("main.js"),
    content=(
      #|false
    ),
  )
  @debug.debug_inspect(
    is_command("GEN"),
    content=(
      #|false
    ),
  )
}

///|
test "drop_first 丢弃前 n 项（含越界与 0）" {
  let a = ["gen", "examples", "src"]
  @debug.debug_inspect(
    drop_first(a, 0),
    content=(
      #|["gen", "examples", "src"]
    ),
  )
  @debug.debug_inspect(
    drop_first(a, 1),
    content=(
      #|["examples", "src"]
    ),
  )
  @debug.debug_inspect(
    drop_first(a, 3),
    content=(
      #|[]
    ),
  )
  @debug.debug_inspect(
    drop_first(a, 9),
    content=(
      #|[]
    ),
  )
}

///|
test "is_sep 把正斜杠与反斜杠都当分隔符" {
  @debug.debug_inspect(
    is_sep(47),
    content=(
      #|true
    ),
  )
  @debug.debug_inspect(
    is_sep(92),
    content=(
      #|true
    ),
  )
  @debug.debug_inspect(
    is_sep(65),
    content=(
      #|false
    ),
  )
}

///|
test "dir_of：目录部分（无分隔符退化为当前目录）" {
  @debug.debug_inspect(
    dir_of("a/b/c.mbt"),
    content=(
      #|"a/b"
    ),
  )
  @debug.debug_inspect(
    dir_of("c.mbt"),
    content=(
      #|"."
    ),
  )
  @debug.debug_inspect(
    dir_of("/x"),
    content=(
      #|"/"
    ),
  )
  // 相对路径 + 反斜杠同样要能拆
  @debug.debug_inspect(
    dir_of("a\\b\\c.mbt") == "a\\b",
    content=(
      #|true
    ),
  )
}

///|
test "base_name：文件名部分" {
  @debug.debug_inspect(
    base_name("a/b/c.mbt"),
    content=(
      #|"c.mbt"
    ),
  )
  @debug.debug_inspect(
    base_name("c.mbt"),
    content=(
      #|"c.mbt"
    ),
  )
  @debug.debug_inspect(
    base_name("a\\b\\c.mbt") == "c.mbt",
    content=(
      #|true
    ),
  )
}

///|
test "join_path：拼接时避免重复分隔符" {
  @debug.debug_inspect(
    join_path("a", "b.mbt"),
    content=(
      #|"a/b.mbt"
    ),
  )
  @debug.debug_inspect(
    join_path("a/", "b.mbt"),
    content=(
      #|"a/b.mbt"
    ),
  )
  @debug.debug_inspect(
    join_path("", "b.mbt"),
    content=(
      #|"b.mbt"
    ),
  )
}

///|
test "last_sep：找不到分隔符返回 -1（排序稳定性依赖它）" {
  @debug.debug_inspect(
    last_sep("a/b"),
    content=(
      #|1
    ),
  )
  @debug.debug_inspect(
    last_sep("abc"),
    content=(
      #|-1
    ),
  )
}
