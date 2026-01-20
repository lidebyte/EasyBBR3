# 设计：内核级网络优化

## 目标
1. 减少 TCP 首包延迟（慢启动优化）
2. 提升高并发场景吞吐量（端口范围、TIME_WAIT）
3. 优化内存利用（自动调优）
4. 可选：多核网卡分发（RPS/RFS）

## 新增 sysctl 参数

### TCP 初始窗口优化
```bash
# 禁用空闲后慢启动重置，保持连接性能
net.ipv4.tcp_slow_start_after_idle = 0
```

### 内存自动调优
```bash
# 启用接收缓冲区自动调优
net.ipv4.tcp_moderate_rcvbuf = 1
```

### 端口范围扩大
```bash
# 扩大本地端口范围，支持更多并发连接
net.ipv4.ip_local_port_range = 1024 65535
```

### TIME_WAIT 优化
```bash
# 允许 TIME_WAIT 状态的 socket 被复用
net.ipv4.tcp_tw_reuse = 1
# 限制 TIME_WAIT 数量
net.ipv4.tcp_max_tw_buckets = 262144
```

### SYN 队列优化
```bash
# 增大 SYN 队列长度
net.ipv4.tcp_max_syn_backlog = 65535
# 增大监听队列长度
net.core.somaxconn = 65535
```

## 风险评估
- **低风险**：所有参数均为标准 sysctl，不支持的内核会自动跳过
- **兼容性**：Linux 3.x+ 均支持
- **回滚**：删除配置文件并执行 `sysctl --system` 即可恢复

## 实现位置
- 修改 `get_advanced_sysctl_params()` 函数
- 添加到高级优化参数输出中
