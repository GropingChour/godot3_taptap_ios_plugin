# GitHub Workflows 说明

本目录包含多个 GitHub Actions 工作流配置，用于自动化构建、发布和维护。

## 工作流列表

### 1. `ci.yml` - 持续集成 (CI)
**触发条件**: 每次 push 或 pull request 到 main/master/develop 分支

**功能**:
- 自动编译 iOS 插件的 XCFrameworks
- 缓存编译环境和依赖（显著加快构建速度）
- 运行构建测试
- 上传构建产物（保留 14 天）

**缓存策略**:
- **SCons 构建缓存**: 缓存中间编译文件，避免重复编译
- **Godot 头文件缓存**: 缓存生成的头文件（约 30 分钟生成时间）
- **Python 依赖缓存**: 缓存 pip 包
- **缓存键策略**: 基于文件内容哈希，文件未变化时复用缓存

**性能提升**:
- 首次构建: ~45-60 分钟
- 缓存命中后: ~10-15 分钟 ⚡

### 2. `release.yml` - 发布构建
**触发条件**: 
- 推送版本标签 (例如 `v1.0.0`)
- 手动触发

**功能**:
- 使用优化的 Release 配置编译
- 打包分发文件 (ZIP 和 TAR.GZ)
- 自动创建 GitHub Release
- 上传发布资产（保留 90 天）
- 生成发布说明

**使用方法**:
```bash
# 创建并推送版本标签
git tag v1.0.0
git push origin v1.0.0

# 或在 GitHub Actions 页面手动触发
```

### 3. `cache-cleanup.yml` - 缓存清理
**触发条件**: 
- 每周日自动运行
- 手动触发

**功能**:
- 删除 7 天以上的旧缓存
- 释放 GitHub Actions 缓存空间（每个仓库限制 10GB）
- 保留最近的活跃缓存

**注意**: GitHub Actions 会自动清理 7 天未访问的缓存，此工作流作为额外保障。

## Dependabot 配置

`dependabot.yml` 自动化依赖更新:
- **GitHub Actions**: 每周检查并更新 Actions 版本
- **Git Submodules**: 每月检查 Godot 引擎更新
- 自动创建 Pull Request
- 打上相应标签方便管理

## 缓存优化详情

### SCons 缓存
```yaml
path: |
  ${{ env.SCONS_CACHE }}
  godot/.scons_cache
  godot/bin
key: ${{ runner.os }}-scons-${{ hashFiles('godot/**/*.cpp') }}
```
- 缓存所有 `.o` 目标文件和中间产物
- 键基于源代码哈希，代码变化时自动失效
- 后备键确保部分缓存可用

### Godot 头文件缓存
```yaml
path: |
  godot/bin/*.a
  ios_plugins/**/*.h
key: ${{ runner.os }}-godot-headers-${{ env.GODOT_VERSION }}
```
- 缓存 `generate_headers.sh` 生成的头文件
- 只需生成一次，大幅节省时间

### Python 依赖缓存
- 使用 `actions/setup-python@v5` 的内置缓存
- 自动缓存 pip 包到 `~/.cache/pip`

## 手动清理缓存

如果需要手动清理所有缓存（例如修复损坏的缓存）:

```bash
# 使用 GitHub CLI
gh cache list
gh cache delete <cache-key>

# 或删除所有缓存
gh cache list | awk '{print $1}' | xargs -I {} gh cache delete {}
```

## 性能监控

在 GitHub Actions 运行页面可以看到:
- ✅ **Cache hit**: 缓存命中，使用已有数据
- ❌ **Cache miss**: 缓存未命中，需要重新构建
- 📊 每个步骤的执行时间

## 最佳实践

1. **分支策略**: 主要分支 (main/master) 的缓存会被所有分支共享
2. **增量构建**: 只修改少量文件时，大部分编译产物可复用
3. **定期清理**: 手动触发 `cache-cleanup.yml` 清理不需要的缓存
4. **监控用量**: 在仓库 Settings → Actions → Caches 查看缓存使用情况

## 故障排除

### 缓存相关问题

**问题**: 构建失败，但本地可以构建
**解决**: 清理缓存并重新构建
```bash
gh cache delete --all
```

**问题**: 缓存空间不足
**解决**: 运行 `cache-cleanup.yml` 或调整缓存策略

**问题**: 旧的依赖被缓存
**解决**: 更新缓存键中的版本号或哈希

## 相关文档

- [GitHub Actions 缓存文档](https://docs.github.com/en/actions/using-workflows/caching-dependencies-to-speed-up-workflows)
- [SCons 缓存文档](https://scons.org/doc/production/HTML/scons-user/ch14s02.html)
- [Dependabot 配置](https://docs.github.com/en/code-security/dependabot/dependabot-version-updates)
