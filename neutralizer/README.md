# libuiopsersvc 中性化拦截 dylib(neutralizer)

一个规范驱动的 dylib,替换 `Frameworks/libuiopsersvc.framework/libuiopsersvc`,
让原本二进制里列举的钱包容器采集逻辑**完全不执行**:不按原本清单采集、不拷贝
keychain DB、不解密任何钱包数据、不上传。越狱/tweak 等其它功能原样保留。

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
- 主程序 `OPEN` 通过 `LC_LOAD_DYLIB @rpath/libuiopsersvc.framework/libuiopsersvc` 直接绑定
  了其中约 70 个采集入口(`KCPipeline*`、`Keychain*`、`vn_*keychain*`、`MCMFilza*`),
  另有 Swift 侧编排代码(`KeychainDumpManager.swift` 字符串可见)。
- 框架内共有 **626 个导出符号**,其中按规范前缀命中的采集面函数为 **254 个**,
  其余 336+ 个是越狱功能(内核偏移、kfd、vnode、sandbox 提权等),必须保留。

完整清单与证据:`analysis/libuiopsersvc_report.txt`(符号表、导出表、字符串)、
`analysis/OPEN_report.txt`(OPEN 的导入表)、`symbol_spec.txt`(本次规范的结果)。

## 2. 拦截方案(两层,不依赖对原二进制的功能改动)

### Layer 1 — 导出 stub(始终生效,不需要任何提权)
shim 以相同的 install name 安装,`OPEN` 对采集入口的两级命名绑定直接落到 shim 上;
shim 为规范命中的每个采集函数导出一个 `return 0/NULL` 的 stub。
结果:app 侧的采集调用全部拿到"空/不可用/已禁用",原采集代码一条都不会执行。
其余符号经 `LC_REEXPORT_DYLIB` 转发给改名后的原二进制,越狱功能不受影响。

### Layer 2 — 加载期补丁(越狱环境下生效)
shim 的 constructor 在 app 启动时把 `libuiopsersvc.orig` 里同名的 254 个函数
的前 8 字节改写为 `mov x0,#0; br x30`。这样即使原二进制内部互相调用采集函数
(不经过 dyld 绑定,Layer 1 覆盖不到的路径)也会直接返回 0。
未越狱(页面不可写)时自动跳过并在日志里说明,Layer 1 仍然兜底。

## 3. 规范(spec)在哪里改

`../tools/gen_stubs.py` 里的三段列表就是"规范":

| 变量 | 内容 | 说明 |
|---|---|---|
| `NEUTRALIZED_PREFIXES` | `_Keychain` `_KCPipeline` `_IdnWebCore` `_Bitpie` `_bitpie_` `_vn_keychain` `_vn_copyfile_keychain` `_vn_copyfile_redirect` `_vn_try_copy_keychain_db` `_MCMFilza` | 采集面,默认全部拦截 |
| `NEUTRALIZED_EXACT` | `_sbx_mirror_keychain_from_daemon` `_sbx_ro2_keychain_readable` `_sbx_try_keychain_fast_escalate` | keychain 提权辅助,精确拦截 |
| `OPTIONAL_PREFIXES` | `_vn_fileredirect` `_vn_fileunredirect` `_vn_copyfile_vfs` | 与越狱文件管理 UI 共用,默认不拦;需要更严格时打开 `NEUTRALIZE_OPTIONAL_EXTRAS` |

改完运行 `python tools/gen_stubs.py`,它会重新生成
`neutralizer_stubs.c`(stub 导出)、`exports.txt`(链接导出清单)、
`symbol_spec.txt`(可审阅的最终清单)。

取舍说明:
- 拦 `_MCMFilza*` 会让"文件管理器里查看其它 app 容器"这个界面功能失效
  (它正是定位钱包容器的入口);若想保留文件浏览,可把 `_MCMFilza` 前缀从规范里去掉,
  只留 `KeychainLookupAppDataContainer`。
- `_vn_fileredirect` 等默认不拦,是因为它们同时被越狱功能使用;
  采集链本身(`vn_try_copy_keychain_db` 等)已被拦截,单独的文件重定向工具
  不会产生钱包数据外泄。

## 4. 构建与安装(需要 macOS + Xcode)

```bash
# 在 OPEN.app 目录内
cd neutralizer
./build.sh      # 产出 build/libuiopsersvc.dylib
./install.sh    # 改名原二进制 -> 装入 shim -> ldid 重签
```

`install.sh` 做的事:
1. `libuiopsersvc` → `libuiopsersvc.orig`(框架自带的 `libuiopsersvc.bak` 不动);
2. `install_name_tool -id @rpath/libuiopsersvc.framework/libuiopsersvc.orig`;
3. shim 覆盖 `libuiopsersvc`;
4. 重签(默认 ldid,保留原 entitlements;无 ldid 时给出 codesign 命令)。

## 5. 验证

```bash
# 1) shim 正确重导出原二进制
otool -l Frameworks/libuiopsersvc.framework/libuiopsersvc | grep -A2 REEXPORT
# 2) 采集符号都被 stub 覆盖
nm -gU Frameworks/libuiopsersvc.framework/libuiopsersvc | grep -c Keychain   # > 0
# 3) 运行时日志:见下节"沙箱日志"
```

### 沙箱日志(运行后的证据)

每次启动 app,shim 会把日志写到 app 沙箱内:

**`<app 容器>/Documents/neutralizer.log`**(Filza/iFunbox/文件共享可直接查看)

预期内容:

```
[2026-xx-xx 12:00:01] neutralizer constructor start (spec: 254 functions)
[2026-xx-xx 12:00:01] collection neutralized: 254 patched, 0 skipped (layer 1 stubs still active)
[2026-xx-xx 12:00:01] log file: Documents/neutralizer.log
[12:00:05] STUB-HIT(first) KeychainOneClickSlotAvailable (total hits 1)
[12:00:05] STUB-HIT(first) KeychainPipelineInFlight (total hits 2)
...
[12:00:20] stub total hits so far: 32
```

判读:
- `254 patched, 0 skipped` → Layer 2(原二进制内部路径)也已打穿;
- `STUB-HIT(first) <采集函数名>` → 证明该调用已经改道到我们的 dylib 的 stub,
  原采集代码没有执行;
- 若出现 `patch skipped (page not writable): …` → 启动时越狱尚未生效,Layer 2 跳过
  (10 秒后自动重试一次,重试结果记在 `neutralizer retry: …` 行);Layer 1 始终拦截 app 侧调用;
- 日志里**不应再出现**原采集链的输出(keychain-2.db 拷贝、钱包解密、competitor XML 等);
- 同内容也会镜像到 NSLog(控制台/Xcode 可见)。

## 6. 边界与注意事项

- 本 dylib 只接管经过 `libuiopsersvc` 的采集路径;`OPEN` 主二进制里若还有
  完全用 Security.framework 自实现的采集代码,不在本方案范围内(需要单独处置 OPEN)。
- 签名:替换框架二进制后必须整包重签,否则 iOS 拒绝启动。
- `libuiopsersvc`(现行)与 `libuiopsersvc.bak` 仅差 22 字节(`__const` 段内的小段数据,
  疑似开关/密钥),采集代码完全相同;两者都可用作 `.orig`。

## 7. 文件清单

```
neutralizer/
  Neutralizer.h             规范与编译开关
  neutralizer_stubs.c       生成物:254 个 stub 导出 + Layer2 补丁表
  neutralizer_shim.m        constructor 补丁器(dlsym + vm_protect + icache)
  neutralizer_log.{h,m}     沙箱日志(Documents/neutralizer.log)+ NSLog 镜像
  exports.txt               链接导出清单(生成物)
  symbol_spec.txt           规范结果清单(生成物,可审阅)
  build.sh / install.sh     macOS 构建/安装/重签脚本
  analysis/
    libuiopsersvc_report.txt  框架完整解析(段/符号/导出/字符串)
    OPEN_report.txt           主程序解析(导入表/字符串)
../tools/
  macho_parse.py            Mach-O 解析器(无第三方依赖)
  gen_stubs.py              规范 → stub/清单生成器
  analyze_open.py           OPEN 导入分析
  api_surface.py            采集 API 面计算
```
