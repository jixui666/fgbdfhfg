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

## 注入方式(按可靠性排序)

> 注意:`launchctl setenv DYLD_INSERT_LIBRARIES` 在较新的 iOS/rootless 越狱上
> **不会**传给 SpringBoard 拉起的 app,所以别用这种方式测,用下面的 A1/A2。

### A1. SSH 直接拉起 app 二进制(最可靠,测试首选)

```bash
# 设备上(SSH):
scp neutralizer.dylib root@<device>:/var/mobile/
ldid -S /var/mobile/neutralizer.dylib     # CI 产物已签过名,可跳过
DYLD_INSERT_LIBRARIES=/var/mobile/neutralizer.dylib \
  /var/containers/Bundle/Application/*/OPEN.app/OPEN
```

### A2. TweakInject(ellekit/palera1n rootless 等)

```bash
cp neutralizer.dylib /var/jb/usr/lib/TweakInject/neutralizer.dylib
```

配一个 plist(同目录,文件名如 `neutralizer.plist`):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Filter</key>
  <dict>
    <key>Bundles</key>
    <array><string>com.apple.mobile.MobileHouseArrest</string></array>
  </dict>
</dict></plist>
```

然后 respring,再正常打开 OPEN。

### B. insert_dylib 加 LC_LOAD_DYLIB(注意局限)

普通 `LC_LOAD_DYLIB` **不触发 dyld 插桩**,Layer 1 的 stub 不会接管 app 侧调用;
此方式只有 Layer 2(越狱 + 可写代码页)生效。要验证完整拦截请用 A1/A2。

## 运行后验证

日志同时写到三处(哪个能写写哪个):

- `<app 数据容器>/Documents/neutralizer.log`(即 `$HOME/Documents/neutralizer.log`)
- `/var/mobile/Documents/neutralizer.log`
- `/tmp/neutralizer.log`

另镜像到 NSLog(设备 Console/Xcode 可见)。**只要 dylib 被加载,至少 `/tmp/neutralizer.log`
里一定会有构造日志**;如果三处都没有日志 = dylib 根本没被加载,先检查注入方式。

```
[..] neutralizer constructor start (inject mode, spec: 254 functions)
[..] diag: images=NN self_idx=N fw_idx=N
[..] diag: HOME=/var/mobile/Containers/Data/Application/…
[..] diag: DYLD_INSERT_LIBRARIES=/var/mobile/neutralizer.dylib
[..] POLICY mode=block-all (no collection compiled in)
[..] POLICY selected target: im.token.app (agrp pattern: im.token) - BLOCKED like all others
[..] POLICY original-list[00] im.token.app -> BLOCKED (selected target)
[..] POLICY original-list[01] vip.mytokenpocket -> BLOCKED
      ...
[..] diag: patching framework image …/libuiopsersvc.framework/libuiopsersvc
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
