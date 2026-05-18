# CI/CD with Jenkins

本项目是 DevEco Studio / Hvigor 构建的 HarmonyOS 应用。CI/CD 使用 Jenkins 本地流水线完成自动测试、构建和产物归档。

1. 检查 Jenkins 节点上的 DevEco 命令行环境。
2. 检查关键工程文件是否存在。
3. 运行 `tests/ci-smoke.test.mjs` 自动化冒烟测试。
4. 执行 Hvigor 构建，并归档 `.app` / `.hap` 产物。

## 本机命令

在这台 Mac 上，DevEco Studio 安装在：

```sh
/Applications/DevEco-Studio.app
```

Jenkins shell 环境需要设置：

```sh
export DEVECO_HOME=/Applications/DevEco-Studio.app/Contents
export DEVECO_SDK_HOME=$DEVECO_HOME/sdk
export PATH=$DEVECO_HOME/tools/node/bin:$DEVECO_HOME/tools/ohpm/bin:$DEVECO_HOME/tools/hvigor/bin:$PATH
```

本地验证命令：

```sh
/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw clean assembleApp --no-daemon --no-incremental --no-type-check
```

当前项目已验证该命令可以成功构建。

## Jenkins 配置

推荐建一个 Pipeline Job：

1. Jenkins 新建任务，类型选择 `Pipeline`。
2. 如果仓库已经推到 GitHub/Gitee，`Pipeline` 配置选择 `Pipeline script from SCM`，分支填 `*/main`，脚本路径填 `Jenkinsfile`。
3. 如果只是本机课程项目，也可以先选择 `Pipeline script`，把仓库里的 `Jenkinsfile` 内容贴进去。
4. `Jenkinsfile` 已配置 `pollSCM('H/5 * * * *')`，Jenkins 会定期检查 `main` 分支提交并自动触发。也可以额外配置 Git webhook，让提交后立即触发。

流水线阶段：

| 阶段 | 作用 |
| --- | --- |
| `Environment` | 确认 `hvigorw`、`ohpm`、`DEVECO_SDK_HOME` 可用 |
| `Static Checks` | 检查核心配置文件和源码目录 |
| `Run Tests` | 运行 Node 自动化冒烟测试，并生成 `reports/tests/ci-smoke.xml` |
| `Install Dependencies` | 有 OHPM 依赖时执行 `ohpm install --all` |
| `Build` | 执行 `hvigorw clean assembleApp` |
| `Package Check` | 确认 `.app` 和 `.hap` 产物生成 |

构建成功后，Jenkins 会归档：

```text
reports/tests/*.xml
build/outputs/**/*.app
build/outputs/**/*.zip
entry/build/**/outputs/**/*.hap
.hvigor/outputs/build-logs/*.log
```

## 测试说明

仓库已加入 `tests/ci-smoke.test.mjs`，用于满足流水线中的 `run tests` 要求。该测试不依赖额外 npm 包，会检查：

- 应用元数据是否有效。
- `entry` 模块和 `EntryAbility` 是否存在。
- `main_pages.json` 引用的页面文件是否存在。
- 路由表是否包含首页、笔记本列表和编辑器等核心页面。
- 领域层、数据层和页面层关键源码是否存在。

报告里可以说明：

- CI：每次提交后自动检查环境、执行自动化冒烟测试、完成 Hvigor 构建。
- CD：构建成功后自动归档可安装包，后续可以接入应用市场、测试设备安装或制品库发布。
- 当前测试阶段：已接入自动化冒烟测试，后续可为 `domain/usecases` 添加更细粒度的单元测试。

## 注意签名

当前 `build-profile.json5` 使用本机 `/Users/qc/.ohos/config/` 下的调试签名材料。Jenkins 必须能访问这些文件，否则构建会在签名阶段失败。

更正式的做法是把证书、profile 和密码放进 Jenkins Credentials，再在流水线中生成或替换签名配置；课程项目本机演示可以先沿用当前调试签名。
