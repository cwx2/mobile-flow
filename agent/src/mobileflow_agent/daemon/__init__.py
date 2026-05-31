"""
Daemon 模块（后台运行管理）

模块职责：
  1. Agent 后台运行（daemon start/stop）
  2. 独占锁文件防止多实例
  3. 状态文件持久化（daemon.state.json）
  4. HTTP 控制服务器（127.0.0.1）
  5. 心跳循环（60s）
  6. 系统服务注册（launchd/systemd）

参考实现：
  - Happy daemon/run.ts
"""
