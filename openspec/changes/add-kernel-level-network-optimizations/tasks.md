## 1. 实现
- [x] 1.1 在 `get_advanced_sysctl_params()` 添加 TCP 慢启动优化参数
- [x] 1.2 添加内存自动调优参数
- [x] 1.3 添加端口范围和 TIME_WAIT 优化参数
- [x] 1.4 添加 SYN 队列优化参数
- [x] 1.5 更新优化方案显示（show_optimization_plan）

## 2. 验证
- [ ] 2.1 语法检查（shellcheck 或手动）
- [ ] 2.2 在测试环境验证参数应用
- [ ] 2.3 确认旧内核自动跳过不支持参数

## 3. 文档
- [ ] 3.1 更新 README（如有必要）
