using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Threading;
using System.Collections.Generic;
using System.Management; // 需要安装 System.Management NuGet 包

namespace SteamWrapper
{
    internal static class Program
    {
        [STAThread]
        private static int Main(string[] args)
        {
            try
            {
                string baseDir = AppContext.BaseDirectory.TrimEnd(Path.DirectorySeparatorChar);
                string chsExe = Path.Combine(baseDir, "nine_kokoiro_chs.exe");

                if (!File.Exists(chsExe))
                {
                    // 简单返回非0（也可弹窗提示）
                    return 1;
                }

                var psi = new ProcessStartInfo
                {
                    FileName = chsExe,
                    Arguments = string.Join(" ", Array.ConvertAll(args, a => $"\"{a}\"")),
                    WorkingDirectory = baseDir,
                    UseShellExecute = false,
                    CreateNoWindow = true
                };

                using var p = Process.Start(psi);
                if (p == null) return 2;

                int rootPid = p.Id;

                // 等待主进程及其所有后代进程全部退出
                WaitForProcessAndDescendantsExit(rootPid);

                // 最后返回主进程退出码（若无法获取则返回0）
                try
                {
                    if (!p.HasExited) p.WaitForExit();
                    return p.ExitCode;
                }
                catch
                {
                    return 0;
                }
            }
            catch
            {
                return 10;
            }
        }

        private static void WaitForProcessAndDescendantsExit(int rootPid)
        {
            // 循环检测：只要存在 root 或其任一后代就继续等待
            while (true)
            {
                bool rootAlive = ProcessExists(rootPid);
                bool anyDescendants = false;
                try
                {
                    anyDescendants = AnyDescendantsAlive(rootPid);
                }
                catch
                {
                    // 若 WMI 查询失败（权限/平台问题），退回到按照可执行名检测的策略
                    anyDescendants = FallbackDetectByExeName(rootPid);
                }

                if (!rootAlive && !anyDescendants) break;

                Thread.Sleep(1000);
            }
        }

        private static bool ProcessExists(int pid)
        {
            try
            {
                Process.GetProcessById(pid);
                return true;
            }
            catch
            {
                return false;
            }
        }

        private static bool AnyDescendantsAlive(int rootPid)
        {
            // 使用 WMI 查找 ParentProcessId 链（递归）
            var toCheck = new Queue<int>();
            toCheck.Enqueue(rootPid);

            while (toCheck.Count > 0)
            {
                int parent = toCheck.Dequeue();
                string q = $"Select ProcessId from Win32_Process Where ParentProcessId = {parent}";
                using var searcher = new ManagementObjectSearcher(q);
                using var results = searcher.Get();
                foreach (ManagementObject mo in results)
                {
                    try
                    {
                        var childPidObj = mo["ProcessId"];
                        if (childPidObj == null) continue;
                        int childPid = Convert.ToInt32(childPidObj);
                        if (ProcessExists(childPid)) return true;
                        // 继续向下查找该 child 的后代（以防 CHS 创建了多级子进程）
                        toCheck.Enqueue(childPid);
                    }
                    catch
                    {
                        // 忽略单个 process 查询错误，继续查别的
                    }
                }
            }

            return false;
        }

        private static bool FallbackDetectByExeName(int rootPid)
        {
            // WMI 不可用时的保底策略：检测与 rootPid 启动时间接近的相关 exe 名称是否存在。
            // 这种方法不如 WMI 精确，但通常能覆盖常见场景。
            try
            {
                var rootProc = Process.GetProcessById(rootPid);
                var rootStart = rootProc.StartTime;

                // 常见可疑 exe 名称（根据你游戏实际的 exe 名称调整）
                string[] suspectNames = new[] { "nine_kokoiro", "nine_kokoiro_chs" };

                foreach (var name in suspectNames)
                {
                    var procs = Process.GetProcessesByName(name);
                    foreach (var pr in procs)
                    {
                        try
                        {
                            // 只认为启动时间 >= rootStart - 5s 的进程为后代（避免误匹配旧进程）
                            if (pr.StartTime >= rootStart.AddSeconds(-5)) return true;
                        }
                        catch { }
                    }
                }
            }
            catch { }

            return false;
        }
    }
}
