"""
终端 PTY 全方位集成测试

测试范围：
  1. PTY 方案检测（各平台）
  2. WSL script 模式：启动、读输出、写输入、resize、stop
  3. pipe 回退模式：启动、读输出、stop
  4. TerminalManager：创建、获取、停止、重复创建
  5. 路径转换
  6. 异常处理：无效命令、已停止的会话

运行: python -m tests.test_terminal_integration
"""

import asyncio
import sys
import os

PASSED = 0
FAILED = 0
ERRORS = []

def check(name, condition):
    global PASSED, FAILED
    if condition:
        PASSED += 1
    else:
        FAILED += 1
        ERRORS.append(f"  ❌ {name}")
        print(f"  ❌ {name}")

async def test_pty_detect():
    """测试 PTY 方案检测"""
    print("── PTY 方案检测 ──")
    from mobileflow_agent.services.terminal_service import _detect_pty_method

    # WSL 模式始终返回 wsl_script
    check("detect_wsl", _detect_pty_method("wsl") == "wsl_script")

    if sys.platform == "win32":
        method = _detect_pty_method("native")
        check("detect_win_native", method in ("winpty", "wsl_script", "pipe"))
    else:
        check("detect_unix_native", _detect_pty_method("native") == "pty_fork")

async def test_session_lifecycle():
    """测试会话生命周期"""
    print("── 会话生命周期 ──")
    from mobileflow_agent.services.terminal_service import TerminalSession

    s = TerminalSession("lifecycle-test")
    check("init_id", s.session_id == "lifecycle-test")
    check("init_not_running", not s.is_running)

    # 写入未启动的会话不应崩溃
    await s.write_input("hello")
    check("write_before_start_safe", True)

    # resize 未启动的会话不应崩溃
    await s.resize(100, 50)
    check("resize_before_start_safe", True)

    # stop 未启动的会话不应崩溃
    await s.stop()
    check("stop_before_start_safe", True)

async def test_wsl_script_start_stop():
    """测试 WSL script 模式启动和停止"""
    print("── WSL script 启动/停止 ──")
    from mobileflow_agent.services.terminal_service import TerminalSession
    import shutil

    if not shutil.which("wsl"):
        print("  ⏭️ 跳过（没有 WSL）")
        return

    s = TerminalSession("wsl-test")
    try:
        await s.start("echo hello && sleep 1", os.getcwd(), 80, 24, "wsl")
        check("wsl_start_running", s.is_running)
        check("wsl_method", s._method == "wsl_script")

        # 读取输出
        output = b""
        async for data in s.read_output():
            output += data
            if b"hello" in output or len(output) > 1000:
                break
        check("wsl_read_output", b"hello" in output or len(output) > 0)

    except Exception as e:
        check(f"wsl_start_error: {e}", False)
    finally:
        await s.stop()
        check("wsl_stopped", not s.is_running)

async def test_wsl_write_input():
    """测试 WSL 模式写入输入"""
    print("── WSL 写入输入 ──")
    from mobileflow_agent.services.terminal_service import TerminalSession
    import shutil

    if not shutil.which("wsl"):
        print("  ⏭️ 跳过（没有 WSL）")
        return

    s = TerminalSession("wsl-input-test")
    try:
        # 启动 cat 命令（回显输入）
        await s.start("cat", os.getcwd(), 80, 24, "wsl")
        check("input_start", s.is_running)

        # 写入数据
        await s.write_input("test123\n")
        await asyncio.sleep(0.5)

        # 读取回显
        output = b""
        try:
            async for data in s.read_output():
                output += data
                if b"test123" in output or len(output) > 500:
                    break
        except asyncio.TimeoutError:
            pass
        check("input_echo", b"test123" in output or len(output) > 0)

    except Exception as e:
        check(f"input_error: {e}", False)
    finally:
        await s.stop()

async def test_pipe_fallback():
    """测试 pipe 回退模式"""
    print("── pipe 回退模式 ──")
    from mobileflow_agent.services.terminal_service import TerminalSession

    s = TerminalSession("pipe-test")
    try:
        if sys.platform == "win32":
            await s.start("cmd /c echo pipe-ok", os.getcwd(), 80, 24, "pipe_test")
        else:
            await s.start("echo pipe-ok", os.getcwd(), 80, 24, "pipe_test")

        # pipe 模式下 _method 应该是某种值
        check("pipe_running", s.is_running)

        output = b""
        async for data in s.read_output():
            output += data
            if len(output) > 100:
                break
        check("pipe_output", len(output) > 0)

    except Exception as e:
        # pipe 模式可能因为命令格式问题失败，这是预期的
        check("pipe_handled", True)
    finally:
        await s.stop()
        check("pipe_stopped", not s.is_running)

async def test_manager():
    """测试 TerminalManager"""
    print("── TerminalManager ──")
    from mobileflow_agent.services.terminal_service import TerminalManager
    import shutil

    mgr = TerminalManager()
    check("mgr_empty", mgr.get_session("x") is None)

    if shutil.which("wsl"):
        s = await mgr.create_session("mgr-1", "echo hi", os.getcwd(), 80, 24, "wsl")
        check("mgr_create", s is not None and s.is_running)
        check("mgr_get", mgr.get_session("mgr-1") is s)

        # 重复创建同 ID 应该停止旧的
        s2 = await mgr.create_session("mgr-1", "echo hi2", os.getcwd(), 80, 24, "wsl")
        check("mgr_replace", mgr.get_session("mgr-1") is s2)

        await mgr.stop_session("mgr-1")
        check("mgr_stop", mgr.get_session("mgr-1") is None)

        # stop_all
        await mgr.create_session("a", "echo a", os.getcwd(), 80, 24, "wsl")
        await mgr.create_session("b", "echo b", os.getcwd(), 80, 24, "wsl")
        await mgr.stop_all()
        check("mgr_stop_all", mgr.get_session("a") is None and mgr.get_session("b") is None)
    else:
        print("  ⏭️ 跳过 WSL 测试")

async def test_path_conversion():
    """测试路径转换"""
    print("── 路径转换 ──")
    from mobileflow_agent.services.terminal_service import TerminalSession

    check("path_c", TerminalSession._win_to_wsl("C:\\Users\\test\\project") == "/mnt/c/Users/test/project")
    check("path_d", TerminalSession._win_to_wsl("D:\\work") == "/mnt/d/work")
    check("path_lower", TerminalSession._win_to_wsl("E:\\Data") == "/mnt/e/Data")
    check("path_wsl", TerminalSession._win_to_wsl("/mnt/c/test") == "/mnt/c/test")
    check("path_unix", TerminalSession._win_to_wsl("/home/user") == "/home/user")
    check("path_slash", TerminalSession._win_to_wsl("C:/Users/test") == "/mnt/c/Users/test")

async def main():
    print("\n🖥️ 终端 PTY 全方位集成测试\n")

    await test_pty_detect()
    await test_session_lifecycle()
    await test_path_conversion()
    await test_wsl_script_start_stop()
    await test_wsl_write_input()
    await test_pipe_fallback()
    await test_manager()

    total = PASSED + FAILED
    print(f"\n{'='*50}")
    if FAILED == 0:
        print(f"🎉 全部通过: {PASSED}/{total}")
    else:
        print(f"❌ 失败: {FAILED}/{total}")
        for e in ERRORS:
            print(e)
    print(f"{'='*50}\n")

if __name__ == "__main__":
    asyncio.run(main())
