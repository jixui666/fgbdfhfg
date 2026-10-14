# libuiopsersvc neutralizer(钱包采集中性化拦截 dylib)

GitHub Actions 编译出**单个 dylib**,注入后让
`libuiopsersvc` 原本内置的钱包容器/keychain 采集链**完全不执行**:
不按原本清单采集、不拷贝 keychain DB、不解密、不上传;越狱/tweak 等其它功能保留。

**策略:block-all(只拦截,不采集)**。dylib 内不含任何采集能力;
策略日志会把原本清单里的每个钱包(含指定目标 imToken)的拦截决策逐条写进沙箱日志,
用于验证"不按原本清单采集、按 dylib 规范走"的拦截能力。

**⚠️ 仓库隐私**:`vendor/` 下的 `libuiopsersvc` 是待分析的不可信二进制
(内含钱包采集逻辑)。请保持仓库 **private**,不要把 vendor 样本公开传播。

## 用 Actions 编译

每次 push 到 `main`/`master` 或手动点 **Run workflow** 即触发;
产物在 Action 的 **Artifacts → neutralizer-dylib** 里,只有一个文件:

```
neutralizer.dylib
```

## 注入方式(二选一,都不需要替换/改名框架里的文件)

### A. DYLD_INSERT_LIBRARIES(越狱环境,推荐测试用)

把 `neutralizer.dylib` 放到设备上(如 `/var/mobile/neutralizer.dylib`),然后:

```bash
launchctl setenv DYLD_INSERT_LIBRARIES /var/mobile/neutralizer.dylib
# 重新启动 OPEN(app 由 SpringBoard 拉起时继承该环境变量)
```

测完清除:`launchctl unsetenv DYLD_INSERT_LIBRARIES`

### B. 给 OPEN 加 LC_LOAD_DYLIB(固化注入)

macOS 上用 insert_dylib/optool:

```bash
cp neutralizer.dylib OPEN.app/neutralizer.dylib
insert_dylib @executable_path/neutralizer.dylib OPEN.app/OPEN
# 整包重签(必须)
ldid -S OPEN.app   # 或 codesign -f -s "..." --deep OPEN.app
```

## 运行后验证

沙箱日志 **`<app 容器>/Documents/neutralizer.log`**:

```
[..] neutralizer constructor start (inject mode, spec: 254 functions)
[..] POLICY mode=block-all (no collection compiled in)
[..] POLICY selected target: im.token.app (agrp pattern: im.token) - BLOCKED like all others
[..] POLICY original-list[00] im.token.app -> BLOCKED (selected target)
[..] POLICY original-list[01] vip.mytokenpocket -> BLOCKED
      ...
[..] layer 2: 254 patched, 0 skipped (layer 1 stubs still active)
[..] STUB-HIT(first) KeychainOneClickSlotAvailable (total hits 1)
[..] POLICY MCMFilzaDataContainerPath(id=(n/a)) -> BLOCKED (original-list=no, target-imToken=no, mode=block-all)
```

判读:
- `STUB-HIT(first) <采集函数>` = 该调用已改道进我们的 dylib;
- `POLICY … -> BLOCKED` = 策略决策在 dylib 内生效(含 imToken 在内全部阻止);
- `layer 2: 254 patched` = 原二进制内部路径也已打穿(越狱环境;未越狱时记 skipped,
  5s/15s 自动重试,Layer 1 始终兜底);
- 日志里不应再出现原采集链输出(keychain-2.db 拷贝、钱包解密、competitor XML)。

细节(两层设计、规范修改)见 [neutralizer/README.md](neutralizer/README.md)。

## 仓库布局

```
neutralizer/             dylib 源码、策略、规范产物、build 脚本
tools/                   Mach-O 解析器、规范生成器(gen_stubs.py)
vendor/libuiopsersvc.framework/
    libuiopsersvc        分析/规范输入:现行框架二进制(CI 只在生成 stub 时读取)
    libuiopsersvc.bak    参考:被替换前的原本二进制
.github/workflows/       CI 构建流水线
```
