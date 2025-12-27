using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Threading;
using System.Collections.Generic;
using System.Management;
using System.Runtime.Versioning;
using System.Text.Json;

[assembly: SupportedOSPlatform("windows")]

namespace SteamWrapper
{
    internal static class Program
    {
        [STAThread]
        private static int Main(string[] args)
        {
            try
            {
                // ✅ 关键修复：永远以自身 exe 所在目录为准
                string exePath = Environment.ProcessPath!;
                string baseDir = Path.GetDirectoryName(exePath)!;

                var config = LoadOrCreateConfig(baseDir);
                if (config == null)
                {
                    // 首次运行，已生成配置文件
                    return 0;
                }

                string launcherPath = Path.Combine(baseDir, config.LauncherExe);
                if (!File.Exists(launcherPath))
                {
                    Console.WriteLine($"找不到启动文件：{launcherPath}");
                    return 1;
                }

                var psi = new ProcessStartInfo
                {
                    FileName = launcherPath,
                    Arguments = string.Join(" ", args.Select(a => $"\"{a}\"")),
                    WorkingDirectory = baseDir,
                    UseShellExecute = false,
                    CreateNoWindow = true
                };

                using var p = Process.Start(psi);
                if (p == null) return 2;

                if (config.WaitForChildProcessTree)
                {
                    WaitForProcessAndDescendantsExit(p.Id);
                }
                else
                {
                    p.WaitForExit();
                }

                return p.ExitCode;
            }
            catch
            {
                return 10;
            }
        }

        // ================= 配置文件 =================

        private static WrapperConfig? LoadOrCreateConfig(string baseDir)
        {
            string configPath = Path.Combine(baseDir, "wrapper.config.json");
            string guidePath = Path.Combine(baseDir, "SteamWrapper使用指南.txt");

            if (!File.Exists(configPath))
            {
                var cfg = new WrapperConfig
                {
                    LauncherExe = "nine_kokoiro_chs.exe",
                    WaitForChildProcessTree = true
                };

                File.WriteAllText(
                    configPath,
                    JsonSerializer.Serialize(cfg, new JsonSerializerOptions { WriteIndented = true })
                );

                File.WriteAllText(
                    guidePath,
@"SteamWrapper 使用指南

本程序用于让 Steam 正确统计
汉化版 / 启动器游戏的游玩时间。

使用方法：
1. 修改 wrapper.config.json
2. 将 ""LauncherExe"" 改成你真正要启动的可执行文件名（相对于本程序所在目录）
3. 根据需要设置 ""WaitForChildProcessTree"" 为 true/false（默认 true）
4. Steam 启动本程序即可
");
                Console.WriteLine("已生成默认配置文件，请修改后重新启动。");
                return null;
            }

            return JsonSerializer.Deserialize<WrapperConfig>(File.ReadAllText(configPath));
        }

        // ================= 进程树等待 =================

        private static void WaitForProcessAndDescendantsExit(int rootPid)
        {
            while (true)
            {
                if (!ProcessExists(rootPid) && !AnyDescendantsAlive(rootPid))
                    break;

                Thread.Sleep(1000);
            }
        }

        private static bool ProcessExists(int pid)
        {
            try { Process.GetProcessById(pid); return true; }
            catch { return false; }
        }

        private static bool AnyDescendantsAlive(int rootPid)
        {
            var queue = new Queue<int>();
            queue.Enqueue(rootPid);

            while (queue.Count > 0)
            {
                int parent = queue.Dequeue();
                using var searcher = new ManagementObjectSearcher(
                    $"Select ProcessId from Win32_Process Where ParentProcessId = {parent}"
                );

                foreach (ManagementObject mo in searcher.Get())
                {
                    int pid = Convert.ToInt32(mo["ProcessId"]);
                    if (ProcessExists(pid)) return true;
                    queue.Enqueue(pid);
                }
            }

            return false;
        }
    }

    internal class WrapperConfig
    {
        public string LauncherExe { get; set; } = "";
        public bool WaitForChildProcessTree { get; set; } = true;
    }
}
