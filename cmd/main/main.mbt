// MoonForge 命令行入口。
//
// 命令：
//   moonforge list-rules            列出已注册的派生规则
//   moonforge explain <file.mbt>    打印解析结果（类型 / 字段 / 注解 / 命中的规则）
//   moonforge gen   <path...>       生成 *_derive_gen.mbt（path 可以是文件或目录）
//   moonforge check <path...>       校验磁盘上的生成物与最新生成结果是否一致（CI 用）
//
// 关于参数解析：`moon run` 在不同后端下传给程序的 argv 前缀不同
// （JS 后端是 [node, main.js, ...]，wasm 后端是 [exe, ...]）。
// 这里用“从第一个已知子命令开始截断”的方式归一化，因此两种后端行为一致。

///|
pub(all) suberror MoonForgeError {
  MoonForgeError(String)
}

// `check` 失败时必须给出**非零退出码**，同时不要在 CI 日志里喷一屏运行时堆栈。
// 核心库没有跨后端的 exit 原语，因此这里按后端分别实现：
//   - JS：走 `process.exit`，退出码干净，无多余输出；
//   - 其他后端（如 wasm-gc）：退化为 `panic()`。友好提示行会先正常打印，
//     之后才出现 wasm 的 `RuntimeError: unreachable` 回溯——退出码同样非零，
//     只是多一段回溯文本。因此 `check` 的 CI 用法统一走默认的 js 后端。

///|
#cfg(target="js")
extern "js" fn js_exit(code : Int) -> Unit =
  #| function(code) {
  #|   if (typeof process !== "undefined" && typeof process.exit === "function") {
  #|     process.exit(code);
  #|   }
  #| }

///|
#cfg(target="js")
fn exit_with(code : Int) -> Unit {
  js_exit(code)
}

///|
#cfg(not(target="js"))
fn exit_with(_code : Int) -> Unit {
  panic()
}

///|
fn usage() -> String {
  let b = StringBuilder()
  b.write_string(
    "moonforge " +
    @forge.MOONFORGE_VERSION +
    " — MoonBit 派生代码生成器\n",
  )
  b.write_string("\n")
  b.write_string("用法：\n")
  b.write_string(
    "  moonforge list-rules             列出已注册的派生规则\n",
  )
  b.write_string(
    "  moonforge explain <file.mbt>     打印解析结果（类型 / 字段 / 注解 / 命中规则）\n",
  )
  b.write_string(
    "  moonforge gen   <path...>        生成 *_derive_gen.mbt（path 可为文件或目录）\n",
  )
  b.write_string(
    "  moonforge check <path...>        校验生成物是否有漂移（CI 用，有漂移则非零退出）\n",
  )
  b.write_string("\n")
  b.write_string(
    "派生入口（写进类型所在文件，不是注释）：\n",
  )
  b.write_string(
    "  pub impl @derive.DeriveFieldNames for User with fn requested(_self) {}\n",
  )
  b.to_string()
}

///|
fn is_command(s : String) -> Bool {
  s == "gen" ||
  s == "check" ||
  s == "list-rules" ||
  s == "explain" ||
  s == "help" ||
  s == "--help" ||
  s == "-h"
}

///|
/// 把宿主注入的 argv 前缀削掉，只保留属于本 CLI 的参数。
fn cli_args() -> Array[String] {
  let out : Array[String] = []
  let mut started = false
  for a in @env.args() {
    if !started && is_command(a) {
      started = true
    }
    if started {
      out.push(a)
    }
  }
  out
}

///|
/// 丢弃前 n 个元素。
fn drop_first(a : Array[String], n : Int) -> Array[String] {
  let out : Array[String] = []
  let mut i = n
  while i < a.length() {
    out.push(a[i])
    i = i + 1
  }
  out
}

///|
fn is_sep(c : UInt16) -> Bool {
  c == 47 || c == 92
}

///|
fn last_sep(path : String) -> Int {
  let mut idx = -1
  let mut i = path.length() - 1
  while i >= 0 && idx < 0 {
    if is_sep(path.at(i)) {
      idx = i
    }
    i = i - 1
  }
  idx
}

///|
fn dir_of(path : String) -> String {
  let idx = last_sep(path)
  if idx < 0 {
    "."
  } else if idx == 0 {
    path[0:1].to_owned()
  } else {
    path[0:idx].to_owned()
  }
}

///|
fn base_name(path : String) -> String {
  let idx = last_sep(path)
  if idx < 0 {
    path
  } else {
    path[idx + 1:].to_owned()
  }
}

///|
fn join_path(dir : String, name : String) -> String {
  if dir.length() == 0 {
    name
  } else if is_sep(dir.at(dir.length() - 1)) {
    dir + name
  } else {
    dir + "/" + name
  }
}

///|
/// 把一个路径（文件或目录）展开成待处理的源文件列表。
///
/// 目录只扫描一层，避免误扫 `target/` 等构建产物；结果排序以保证输出稳定。
///
/// 路径有问题时**抛错**而不是返回空列表：`check` 是 CI 的判据，如果路径
/// 写错了却安静地返回 0，CI 会显示绿色 —— 但一个文件都没检查。
/// 这类"假绿"比报错难查得多。
fn collect_sources(path : String) -> Array[String] raise {
  if !@fs.path_exists(path) {
    raise MoonForgeError(
      "找不到路径：" +
      path +
      "\n    用法：moonforge <gen|check> <path...>，路径可以是 .mbt 文件或目录",
    )
  }
  let out : Array[String] = []
  if @fs.is_dir(path) {
    for name in @fs.read_dir(path) {
      if @forge.is_source_file(name) {
        out.push(join_path(path, name))
      }
    }
  } else if @forge.is_source_file(path) {
    out.push(path)
  } else {
    raise MoonForgeError(
      path + " 不是 .mbt 源文件（本工具只处理 .mbt）",
    )
  }
  out.sort()
  if out.length() == 0 {
    raise MoonForgeError(path + " 下没有找到 .mbt 源文件")
  }
  out
}

///|
fn cmd_list_rules() -> Unit {
  println(
    "已注册的派生规则。派生入口是在类型所在文件里写一行真实 trait impl：",
  )
  println("")
  println(
    "    pub impl @derive.DeriveXxx for <类型> with fn requested(_self) {}",
  )
  println("")
  for r in @rules.all() {
    println("  " + @forge.key_of(r))
    println(
      "      标记 " +
      @forge.marker_of(r) +
      "  →  生成 impl " +
      @forge.trait_name_of(r),
    )
    println("      " + @forge.description_of(r))
  }
}

///|
fn print_type(td : @forge.TypeDef) -> Unit {
  println("  " + td.body_label() + " " + td.name + "   (line \{td.line})")
  if td.doc.length() > 0 {
    println("    doc: " + td.doc)
  }
  if td.is_enum() {
    for v in td.variants {
      println("    variant " + v)
    }
  } else {
    for f in td.fields {
      let mut attrs_text = ""
      for a in f.attrs {
        attrs_text = attrs_text + " @" + a.name
        if a.args.length() > 0 {
          attrs_text = attrs_text + "(" + a.args.join(", ") + ")"
        }
      }
      println("    field " + f.name + " : " + f.ty + attrs_text)
    }
  }
  // 老写法不再产生代码，必须显式提示，否则用户只会看到"生成物消失"。
  let legacy = td.legacy_derive_rules()
  if legacy.length() > 0 {
    println(
      "    [!!] doc comment 里的 @derive(" +
      legacy.join(", ") +
      ") 已废弃、不再生成代码；请改用 impl <标记 trait> for " +
      td.name,
    )
  }
}

///|
/// 一条派生请求的展示：用户写的标记 → 命中的规则 → 会不会真的生成代码。
fn print_request(
  d : @forge.ImplDecl,
  td : @forge.TypeDef,
  rules : Array[&@forge.DeriveRule],
) -> Unit {
  let sep = if d.prefix.length() > 0 { "." } else { "" }
  println(
    "    impl " +
    d.prefix +
    sep +
    d.marker +
    " for " +
    d.target +
    "   (line \{d.line})",
  )
  match @forge.find_rule_by_marker(rules, d.marker) {
    Some(r) => {
      // 与 `generate` 走**同一个**输入契约：`explain` 说"会生成"、生成时却
      // 不生成（或反过来），是最难查的一类不一致。两边都从 `DeriveInput`
      // 取输入，这条不一致就没有产生的空间。
      let input = @forge.DeriveInput::requested(td, d.prefix, d.marker, d.line)
      match r.generate(input) {
        Some(_) =>
          println(
            "      [ok] 规则 " +
            @forge.key_of(r) +
            " → 生成 impl " +
            @forge.trait_name_of(r),
          )
        None =>
          println(
            "      [--] 规则 " +
            @forge.key_of(r) +
            " 不适用：" +
            @forge.not_applicable_reason(td),
          )
      }
    }
    None =>
      println(
        "      [!!] 标记 trait `" +
        d.marker +
        "` 未注册（用 `list-rules` 查看可用标记）",
      )
  }
}

///|
fn has_type(types : Array[@forge.TypeDef], name : String) -> Bool {
  let mut found = false
  for t in types {
    if t.name == name {
      found = true
    }
  }
  found
}

///|
fn cmd_explain(file : String) -> Unit raise {
  // 友好报错：把"用户传错参数"和"程序内部出错"区分开，避免直接抛运行期堆栈。
  if !@fs.path_exists(file) {
    raise MoonForgeError(
      "找不到路径：" +
      file +
      "\n    用法：moonforge explain <file.mbt>，例如 moonforge explain examples/models.mbt",
    )
  }
  if @fs.is_dir(file) {
    raise MoonForgeError(
      file +
      " 是目录；explain 只接受单个 .mbt 文件，例如 moonforge explain examples/models.mbt",
    )
  }
  if !@forge.is_source_file(file) {
    raise MoonForgeError(file + " 不是 .mbt 源文件")
  }
  let src = @fs.read_file_to_string(file)
  let parsed = @forge.parse(src)
  let rules = @rules.all()
  println("moonforge explain: " + file)
  println("")
  if parsed.types.length() == 0 && parsed.impls.length() == 0 {
    println(
      "  （未发现顶层 struct / enum 定义，也没有派生标记）",
    )
    return
  }
  for td in parsed.types {
    print_type(td)
    for d in parsed.impls {
      if d.target == td.name {
        print_request(d, td, rules)
      }
    }
  }
  // 指向本文件之外类型的标记：不报错，但要说清楚它为什么不会生效。
  for d in parsed.impls {
    if !has_type(parsed.types, d.target) {
      println(
        "  [!!] impl " +
        d.marker +
        " for " +
        d.target +
        "   (line \{d.line})：本文件里没有名为 " +
        d.target +
        " 的 struct / enum",
      )
    }
  }
  println("")
  println(
    "共 \{parsed.types.length()} 个类型定义，\{parsed.impls.length()} 条派生请求。",
  )
}

///|
fn run_gen(paths : Array[String]) -> Unit raise {
  let rules = @rules.all()
  let mut scanned = 0
  let mut written = 0
  let mut removed = 0
  let mut warned = 0
  for p in paths {
    // 路径有问题时 collect_sources 会直接抛错（退出码 2），不再静默跳过
    let sources = collect_sources(p)
    for f in sources {
      scanned = scanned + 1
      let src = @fs.read_file_to_string(f)
      let name = base_name(f)
      let out = @forge.generate(name, src, rules, @forge.MOONFORGE_VERSION)
      for d in out.diagnostics {
        println("  [warn] " + name + ": " + d)
        warned = warned + 1
      }
      let target = join_path(dir_of(f), @forge.generated_file_name(name))
      if out.has_output {
        @fs.write_string_to_file(target, out.text)
        println("  generated " + target + "  [" + out.applied.join(", ") + "]")
        written = written + 1
      } else if @fs.path_exists(target) {
        // 源文件里的 `@derive` 被删光之后，上一次生成的文件会留在盘上，
        // `check` 会一直报"多余的生成文件"，而 `gen` 又修不好它 ——
        // 用户被卡在一个"照提示做也没用"的循环里（和格式化稳定性同一类问题）。
        // `gen` 的职责是让磁盘状态收敛到"与源文件一致"，所以这里删掉它。
        @fs.remove_file(target)
        println(
          "  removed   " + target + "  [源文件里已没有 @derive 标记]",
        )
        removed = removed + 1
      }
    }
  }
  println("")
  println(
    "moonforge: 扫描 \{scanned} 个源文件，生成 \{written} 个，清理 \{removed} 个，警告 \{warned} 条",
  )
}

///|
fn run_check(paths : Array[String]) -> Unit raise {
  let rules = @rules.all()
  let drift : Array[String] = []
  let mut scanned = 0
  for p in paths {
    // 路径有问题时 collect_sources 会直接抛错（退出码 2），不再静默跳过
    let sources = collect_sources(p)
    for f in sources {
      scanned = scanned + 1
      let src = @fs.read_file_to_string(f)
      let name = base_name(f)
      let out = @forge.generate(name, src, rules, @forge.MOONFORGE_VERSION)
      let target = join_path(dir_of(f), @forge.generated_file_name(name))
      if out.has_output {
        if @fs.path_exists(target) {
          // 归一化换行符后再比：Windows 上 git 会把检出的文件换成 CRLF，
          // 直接按字节比会把"只是换行符不同"误判成内容过期（详见
          // `normalize_newlines` 的文档注释）。
          let actual = @forge.normalize_newlines(
            @fs.read_file_to_string(target),
          )
          if actual != out.text {
            drift.push("内容过期：" + target)
          }
        } else {
          drift.push("缺少生成文件：" + target)
        }
      } else if @fs.path_exists(target) {
        drift.push(
          "多余的生成文件（源文件里已没有 @derive 标记）：" +
          target,
        )
      }
    }
  }
  if drift.length() > 0 {
    for d in drift {
      println("  [drift] " + d)
    }
    println("")
    println(
      "moonforge: 检测到 \{drift.length()} 处生成物漂移（已扫描 \{scanned} 个文件）。",
    )
    println(
      "请运行 `moon run cmd/main -- gen <dir>` 重新生成并提交。",
    )
    exit_with(1)
  }
  println(
    "moonforge: 已扫描 \{scanned} 个源文件，生成物与源文件一致，无漂移",
  )
}

///|
fn run_main() -> Unit raise {
  let args = cli_args()
  if args.length() == 0 {
    println(usage())
    return
  }
  let cmd = args[0]
  if cmd == "list-rules" {
    cmd_list_rules()
  } else if cmd == "help" || cmd == "--help" || cmd == "-h" {
    println(usage())
  } else if cmd == "explain" {
    if args.length() < 2 {
      raise MoonForgeError(
        "explain 需要一个文件路径，例如：moonforge explain examples/models.mbt",
      )
    }
    cmd_explain(args[1])
  } else if cmd == "gen" {
    let paths = drop_first(args, 1)
    if paths.length() == 0 {
      raise MoonForgeError(
        "gen 需要至少一个路径，例如：moonforge gen examples",
      )
    }
    run_gen(paths)
  } else if cmd == "check" {
    let paths = drop_first(args, 1)
    if paths.length() == 0 {
      raise MoonForgeError(
        "check 需要至少一个路径，例如：moonforge check examples",
      )
    }
    run_check(paths)
  } else {
    println(usage())
  }
}

///|
/// 统一兜底：把任何未捕获的错误转成一行人话提示 + 非零退出码，
/// 而不是把 MoonBit 运行期堆栈直接喷给使用者（CI 日志里尤其重要）。
fn main {
  run_main() catch {
    MoonForgeError(msg) => {
      println("moonforge: " + msg)
      exit_with(2)
    }
    _ => {
      println(
        "moonforge: 运行出错（路径不可读、无权限或参数有误）。",
      )
      println("用法：moon run cmd/main -- help")
      exit_with(2)
    }
  }
}
