# libuiopsersvc 中性化拦截 dylib(neutralizer)

一个规范驱动的**单个 dylib**,注入后让原本二进制里列举的钱包容器采集逻辑
**完全不执行**:不按原本清单采集、不拷贝 keychain DB、不解密任何钱包数据、不上传。
越狱/tweak 等其它功能原样保留。

**策略:block-all(只拦截,不采集)**。本 dylib 不编译任何采集能力;策略日志把
每个钱包的拦截决策(含指定目标 imToken)写进沙箱日志,用来验证拦截能力。

---

## 1. 分析结论(为什么这么设计)

对 `libuiopsersvc`(arm64,`com.uiopser.svc`)做静态解析后确认:

- 它的符号表/字符串里内置了一整套钱包采集链:
  - **钱包容器清单(bundle id)**:`im.token.app`、`vip.mytokenpocket`、`pro.tokenpocket.tp`、
    `com.tokenpocket.ios`、`com.global.wallet.ios`、`io.metamask.MetaMask`、`io.metamask`、
    `com.tronlink.hdwallet`、`com.tronlink.wallet`、`com.okex.OKExAppstoreFull`、
    `com.okex.okex`、`com.okex.wallet`、`com.okex.okexwallet`、`com.okx.okx`、`com.okx.wallet`、
    `com.okx.app`、`com.okinc.okex`、`com.okcoin.okex`、`com.okcoin.app`、`org.okx.ios`
    (配合 `FILZA_MCM_IGNORE_CUSTOM_IDENTIFIERS` / `MCMIdentifiers.plist` 做容器定位);
  - **keychain agrp 清单**:Bitpie / Trust / Tonkeeper / Coin98 / Phantom / imToken /
    TokenPocket / OKX / MetaMask 等,`SELECT … FROM genp WHERE agrp LIKE …` 逐钱包抽取;
  - **AKS/securityd 解密与拷贝链**:`KeychainCopyDBToTmpDirect`、`KeychainAKSDecryptDB`、
    `KeychainSecuritydRemoteUnwrapWrappedKey`、`KeychainRemoteDumpWithRemoteCall*`、
    `vn_try_copy_keychain_db`、`IdnWebCoreCopyKeychainDBToTmp` 等;
  - **"竞品 XML" 导出**:`KeychainBuildCompetitorXML`、`IdnWebCoreTakeCompetitorXMLExport`。
- 主程序 `OPEN` 直接绑定其中约 70 个采集入口(`KCPipeline*`、`Keychain*`、
  `vn_*keychain*`、`MCMFilza*`),另有 Swift 侧编排代码(`KeychainDumpManager.swift`)。
- 框架共 **626 个导出符号**,规范前缀命中的采集面函数 **254 个**,其余 336+ 个
  是越狱功能(内核偏移、kfd、vnode、sandbox 提权等),必须保留。

完整清单与证据:`analysis/libuiopsersvc_report.txt`、`analysis/OPEN_report.txt`、
`symbol_spec.txt`(本次规范结果)。

## 2. 拦截方案(单 dylib 注入,两层)

不替换、不改名框架里任何文件。dylib 通过 `DYLD_INSERT_LIBRARIES` 或给 OPEN
加 `LC_LOAD_DYLIB` 注入。

### Layer 1 — 导出 stub 插桩(始终生效,不需要任何提权)
dylib 导出 254 个与采集入口同名的 stub;dyld 插桩规则让 app 对这些符号的
两级命名绑定全部落到 stub 上,返回 `0/NULL`。原采集代码一条都不会执行。
其余符号不受影响,越狱功能照常。

### Layer 2 — 加载期补丁(越狱环境下生效)
constructor 用 `RTLD_FIRST` 句柄定位已加载的 `libuiopsersvc` 镜像(绕开自己的
插桩),把 254 个函数的开头 8 字节改写为 `mov x0,#0; br x30`。框架内部互相调用
采集函数的路径(不经 dyld)也全部归零。未越狱时跳过并记日志,5s/15s 自动重试。

## 3. 规范(spec)在哪里改

`../tools/gen_stubs.py` 里的列表就是"规范":

| 变量 | 内容 | 说明 |
|---|---|---|
| `NEUTRALIZED_PREFIXES` | `_Keychain` `_KCPipeline` `_IdnWebCore` `_Bitpie` `_bitpie_` `_vn_keychain` `_vn_copyfile_keychain` `_vn_copyfile_redirect` `_vn_try_copy_keychain_db` `_MCMFilza` | 采集面,默认全部拦截 |
| `NEUTRALIZED_EXACT` | `_sbx_mirror_keychain_from_daemon` `_sbx_ro2_keychain_readable` `_sbx_try_keychain_fast_escalate` | keychain 提权辅助,精确拦截 |
| `OPTIONAL_PREFIXES` | `_vn_fileredirect` `_vn_fileunredirect` `_vn_copyfile_vfs` | 与越狱文件管理 UI 共用,默认不拦;需要更严格时打开 `NEUTRALIZE_OPTIONAL_EXTRAS` |
| `HAND_WRITTEN_STUBS` | `MCMFilzaDataContainerPath` `MCMFilzaVirtualRoot` `KeychainLookupAppDataContainer` | 手工实现(带策略日志),见 `policy_hooks.m` |

改完运行 `python tools/gen_stubs.py`,重新生成 `neutralizer_stubs.c`、
`exports.txt`、`symbol_spec.txt`。

钱包策略在 [neutralizer_policy.m](neutralizer_policy.m):
`kOriginalWalletBundleIds`(原本清单)、`kPolicyTargetBundleId`(指定目标,当前
imToken)、`kPolicyTargetAgrp`。策略动作**只有 BLOCK**,无采集代码路径。

## 4. 构建与注入

```bash
# macOS + Xcode(CI 里同样执行)
./neutralizer/build.sh            # 产出 build/neutralizer.dylib(CI 里已 ldid 签名)
```

注入(按可靠性排序):
- **A1. SSH 直接拉起 app 二进制**(测试首选):
  `DYLD_INSERT_LIBRARIES=/var/mobile/neutralizer.dylib /var/containers/Bundle/Application/*/OPEN.app/OPEN`
- **A2. TweakInject**(ellekit/rootless):dylib 放 `/var/jb/usr/lib/TweakInject/`,
  配 Filter plist(`Bundles: com.apple.mobile.MobileHouseArrest`),respring;
- **B. insert_dylib 加 LC_LOAD_DYLIB**:注意普通 LC_LOAD_DYLIB 不触发 dyld 插桩,
  Layer 1 不生效,只有 Layer 2(越狱)生效。
- ⚠️ `launchctl setenv DYLD_INSERT_LIBRARIES` 在新系统上对 SpringBoard 拉起的
  app 无效,不要用这种方式测试。

## 5. 验证

日志同时写到三处(哪个能写写哪个),并镜像 NSLog:

- `<app 数据容器>/Documents/neutralizer.log`(即 `$HOME/Documents/neutralizer.log`)
- `/var/mobile/Documents/neutralizer.log`
- `/tmp/neutralizer.log`

**三处都没有日志 = dylib 没被加载**,先排查注入方式(见上)。

```
[..] neutralizer constructor start (inject mode, spec: 254 functions)
[..] POLICY mode=block-all (no collection compiled in)
[..] POLICY selected target: im.token.app (agrp pattern: im.token) - BLOCKED like all others
[..] POLICY original-list[00] im.token.app -> BLOCKED (selected target)
[..] POLICY original-list[01] vip.mytokenpocket -> BLOCKED
     ...
[..] layer 2: 254 patched, 0 skipped (layer 1 stubs still active)
[..] STUB-HIT(first) KeychainOneClickSlotAvailable (total hits 1)
[..] POLICY MCMFilzaDataContainerPath(id=(n/a)) -> BLOCKED (...)
```

判读:
- `STUB-HIT(first) <采集函数>` = 调用已改道进我们的 dylib;
- `POLICY … -> BLOCKED` = 策略在 dylib 内生效(含 imToken 在内全部阻止);
- `layer 2: 254 patched` = 原二进制内部路径也打穿;未越狱时记
  `patch skipped (page not writable)`,5s/15s 重试,Layer 1 始终兜底;
- 不应再出现原采集链输出(keychain-2.db 拷贝、钱包解密、competitor XML)。

## 6. 边界与注意事项

- 本 dylib 只接管经过 `libuiopsersvc` 的采集路径;`OPEN` 里若还有完全自实现的
  采集代码,不在本方案范围内。
- `DYLD_INSERT_LIBRARIES` 注入需要越狱环境;`LC_LOAD_DYLIB` 方式需要整包重签。
- `libuiopsersvc`(现行)与 `libuiopsersvc.bak` 仅差 22 字节(`__const` 段内的小段
  数据,疑似开关/密钥),采集代码完全相同。

## 7. 文件清单

```
neutralizer/
  Neutralizer.h              规范与编译开关
  neutralizer_stubs.c        生成物:254 个 stub 导出 + Layer2 补丁表
  neutralizer_shim.m         constructor 补丁器(dlsym RTLD_FIRST + vm_protect + icache)
  neutralizer_log.{h,m}      沙箱日志(Documents/neutralizer.log)+ NSLog 镜像
  neutralizer_policy.{h,m}   钱包策略(block-all)+ 逐钱包决策日志
  policy_hooks.m             容器定位入口的手工 stub(带策略日志)
  exports.txt                链接导出清单(生成物)
  symbol_spec.txt            规范结果清单(生成物,可审阅)
  build.sh                   macOS 构建脚本
  analysis/                  框架与主程序的完整解析报告
../tools/
  macho_parse.py             Mach-O 解析器(无第三方依赖)
  gen_stubs.py               规范 → stub/清单生成器
  analyze_open.py / api_surface.py  分析工具
```
