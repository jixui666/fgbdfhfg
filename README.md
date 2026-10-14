# libuiopsersvc neutralizer(钱包采集中性化拦截 dylib)

这个仓库用 GitHub Actions 编译一个 dylib,替换
`OPEN.app/Frameworks/libuiopsersvc.framework/libuiopsersvc`,
使原本二进制内置的钱包容器/keychain 采集链**完全不执行**
(不采集、不拷贝 keychain DB、不解密、不上传),越狱/tweak 等其它功能保留。

**⚠️ 仓库隐私**:`vendor/` 下的 `libuiopsersvc` 是待分析的不可信二进制
(内含钱包采集逻辑)。请保持仓库 **private**,不要把 vendor 样本公开传播。

## 用 Actions 编译

- 每次 push 到 `main`/`master` 或手动点 **Run workflow** 即触发;
- 产物在 Action 的 **Artifacts → neutralizer-dylib**:
  - `libuiopsersvc.dylib` — 编译好的 shim(中性化拦截层);
  - `libuiopsersvc.orig` — 已改好 install name 的原二进制(重导出目标)。

## 安装到 app(设备侧)

```bash
# 1. 原二进制改名(若还没改)
mv OPEN.app/Frameworks/libuiopsersvc.framework/libuiopsersvc \
   OPEN.app/Frameworks/libuiopsersvc.framework/libuiopsersvc.orig
# 2. 放入 CI 产物
cp libuiopsersvc.dylib OPEN.app/Frameworks/libuiopsersvc.framework/libuiopsersvc
# 3. 整包重签(必须,否则 iOS 拒启)
ldid -S OPEN.app   # 或 codesign -f -s "..." --deep OPEN.app
```

运行后查看沙箱日志:`Documents/neutralizer.log`。
细节(两层拦截设计、规范修改、验证判读)见
[neutralizer/README.md](neutralizer/README.md)。

## 仓库布局

```
neutralizer/             shim 源码、规范产物、build/install 脚本
tools/                   Mach-O 解析器、规范生成器(gen_stubs.py)
vendor/libuiopsersvc.framework/
    libuiopsersvc        构建输入:现行框架二进制(作为 .orig 重导出目标)
    libuiopsersvc.bak    参考:被替换前的原本二进制
.github/workflows/       CI 构建流水线
```
