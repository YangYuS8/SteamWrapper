import { convertFileSrc, invoke } from "@tauri-apps/api/core";
import { open } from "@tauri-apps/plugin-dialog";
import { getCurrentWindow } from "@tauri-apps/api/window";
import {
  ChevronRight,
  Copy,
  FolderOpen,
  HardDrive,
  ImageIcon,
  Library,
  ListChecks,
  Minus,
  PanelLeftClose,
  PanelLeftOpen,
  Play,
  RefreshCcw,
  Save,
  ScrollText,
  Settings2,
  Square,
  X,
} from "lucide-react";
import { useEffect, useState } from "react";
import steamWrapperIcon from "@/assets/steamwrapper.svg";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { cn } from "@/lib/utils";

type LocalSteamGame = {
  appid: string;
  name: string;
  install_dir?: string;
  cover_path?: string;
};

type ConfiguredProfile = {
  appid: string;
  name: string;
  game_dir: string;
  target: string;
  launch_option: string;
};

type AppPaths = {
  app_data_dir: string;
  profiles_path: string;
  runner_path: string;
  logs_dir: string;
  backups_dir: string;
  cache_dir: string;
};

type RunnerLogEntry = {
  file_name: string;
  path: string;
  content: string;
};

type RunnerStatus = {
  installed: boolean;
  healthy: boolean;
  path: string;
  bundled_version: string | null;
  installed_version: string | null;
  needs_install: boolean;
  needs_update: boolean;
  last_error: string | null;
};

type ViewKey = "library" | "configured" | "logs" | "settings";

const navItems = [
  { key: "library", label: "游戏库", icon: Library },
  { key: "configured", label: "已配置游戏", icon: ListChecks },
  { key: "logs", label: "日志", icon: ScrollText },
  { key: "settings", label: "设置", icon: Settings2 },
] satisfies Array<{ key: ViewKey; label: string; icon: typeof Library }>;

const guideSteps = [
  { title: "扫描", description: "读取本地 Steam 游戏库" },
  { title: "选择", description: "点选游戏并填写目标程序" },
  { title: "保存", description: "生成 Launch Options" },
];

function pathInfo(path: string) {
  const parts = path.split(/[\\/]/).filter(Boolean);
  const fileName = parts.at(-1) ?? "手动添加的游戏";
  const directory = path.slice(0, Math.max(0, path.length - fileName.length)).replace(/[\\/]$/, "");
  const displayName = fileName.replace(/\.[^.]+$/, "") || fileName;
  return { directory, displayName };
}

export function App() {
  const [games, setGames] = useState<LocalSteamGame[]>([]);
  const [profiles, setProfiles] = useState<ConfiguredProfile[]>([]);
  const [logs, setLogs] = useState<RunnerLogEntry[]>([]);
  const [paths, setPaths] = useState<AppPaths | null>(null);
  const [runnerStatus, setRunnerStatus] = useState<RunnerStatus | null>(null);
  const [runnerBusy, setRunnerBusy] = useState(false);
  const [runnerError, setRunnerError] = useState("");
  const [selectedGame, setSelectedGame] = useState<LocalSteamGame | null>(null);
  const [targetPath, setTargetPath] = useState("");
  const [launchOption, setLaunchOption] = useState("");
  const [statusText, setStatusText] = useState("准备就绪");
  const [activeView, setActiveView] = useState<ViewKey>("library");
  const [sidebarCollapsed, setSidebarCollapsed] = useState(false);
  const [isConfigOpen, setConfigOpen] = useState(false);

  useEffect(() => {
    void refreshProfiles();
    void refreshLogs();
    void refreshPaths();
    void refreshRunnerStatus();
  }, []);

  async function refreshProfiles() {
    try {
      const items = await invoke<ConfiguredProfile[]>("list_profiles");
      setProfiles(items);
    } catch (error) {
      setStatusText(`读取配置失败：${String(error)}`);
    }
  }

  async function refreshLogs() {
    try {
      const items = await invoke<RunnerLogEntry[]>("list_runner_logs");
      setLogs(items);
    } catch (error) {
      setStatusText(`读取日志失败：${String(error)}`);
    }
  }

  async function refreshPaths() {
    try {
      const value = await invoke<AppPaths>("get_app_paths");
      setPaths(value);
    } catch (error) {
      setStatusText(`读取路径失败：${String(error)}`);
    }
  }

  async function refreshRunnerStatus() {
    try {
      const value = await invoke<RunnerStatus>("get_runner_status");
      setRunnerStatus(value);
      setRunnerError(value.last_error ?? "");
    } catch (error) {
      const message = `检查 Runner 失败：${String(error)}`;
      setRunnerError(message);
      setStatusText(message);
    }
  }

  async function installOrRepairRunner(command: "install_runner" | "repair_runner") {
    setRunnerBusy(true);
    setRunnerError("");
    try {
      const outcome = await invoke<{ changed: boolean; status: RunnerStatus }>(command);
      setRunnerStatus(outcome.status);
      setRunnerError(outcome.status.last_error ?? "");
      setStatusText(outcome.changed ? "Runner 已安装到稳定路径" : "Runner 已是当前版本，无需重复复制");
    } catch (error) {
      const message = `Runner 操作失败：${String(error)}`;
      setRunnerError(message);
      setStatusText(message);
    } finally {
      setRunnerBusy(false);
    }
  }

  async function generateLaunchOption(appid: string): Promise<boolean> {
    try {
      const option = await invoke<string>("generate_launch_option", { appid });
      setLaunchOption(option);
      setStatusText("已生成启动选项");
      return true;
    } catch (error) {
      const message = `无法生成可用启动选项：${String(error)}`;
      setStatusText(message);
      return false;
    }
  }

  async function scanLocalGames() {
    setStatusText("正在扫描本地 Steam 游戏……");
    try {
      const scanned = await invoke<LocalSteamGame[]>("scan_local_steam_games_command");
      setGames(scanned);
      setStatusText(scanned.length > 0 ? `已找到 ${scanned.length} 个本地 Steam 游戏` : "没有扫描到本地 Steam 游戏");
    } catch (error) {
      setStatusText(`扫描失败：${String(error)}`);
    }
  }

  async function chooseTargetPath() {
    const selected = await open({
      directory: false,
      multiple: false,
      title: "选择真正要启动的程序",
    });

    if (typeof selected === "string") {
      setTargetPath(selected);
      setSelectedGame((current) => {
        if (!current?.appid.startsWith("manual-")) {
          return current;
        }

        const { directory, displayName } = pathInfo(selected);
        return {
          ...current,
          name: current.name === "手动添加的游戏" ? displayName : current.name,
          install_dir: directory || current.install_dir,
        };
      });
      setStatusText("已选择目标程序");
    }
  }

  function createManualGame() {
    const game: LocalSteamGame = {
      appid: `manual-${Date.now()}`,
      name: "手动添加的游戏",
      install_dir: paths?.app_data_dir,
    };

    setGames((current) => [game, ...current]);
    openGameConfig(game);
    setStatusText("已创建手动游戏条目，请选择目标程序后保存");
  }

  function openConfiguredProfile(profile: ConfiguredProfile) {
    const game: LocalSteamGame = {
      appid: profile.appid,
      name: profile.name,
      install_dir: profile.game_dir,
    };

    setSelectedGame(game);
    setTargetPath(profile.target);
    setLaunchOption(profile.launch_option);
    setConfigOpen(true);
    setStatusText(
      runnerStatus?.healthy
        ? `正在编辑：${profile.name}`
        : "Runner 尚不可用，请先到设置页安装或修复后再生成 Launch Options",
    );
  }

  function openGameConfig(game: LocalSteamGame) {
    setSelectedGame(game);
    setTargetPath("");
    setLaunchOption("");
    setConfigOpen(true);
    setStatusText(`正在配置：${game.name}`);
  }

  async function saveCurrentProfile() {
    if (!selectedGame) {
      setStatusText("请先选择一个游戏");
      return;
    }

    if (!selectedGame.install_dir) {
      setStatusText("当前游戏缺少安装目录，暂时无法保存配置");
      return;
    }

    if (!targetPath.trim()) {
      setStatusText("请填写真正要启动的 exe 或 launcher 路径");
      return;
    }

    try {
      await invoke("save_profile", {
        request: {
          appid: selectedGame.appid,
          name: selectedGame.name,
          game_dir: selectedGame.install_dir,
          target: targetPath.trim(),
        },
      });

      const launchOptionReady = await generateLaunchOption(selectedGame.appid);
      await refreshProfiles();
      setStatusText(launchOptionReady ? "配置已保存" : "配置已保存，但 Runner 尚不可用，请先在设置页安装或修复 Runner");
    } catch (error) {
      setStatusText(`保存失败：${String(error)}`);
    }
  }

  function renderContent() {
    switch (activeView) {
      case "configured":
        return (
          <Card>
            <CardHeader className="flex flex-row items-center justify-between gap-4 space-y-0">
              <div>
                <CardTitle>已配置游戏</CardTitle>
                <CardDescription>这里读取本机 profiles.toml，点击条目可以继续编辑。</CardDescription>
              </div>
              <Button data-testid="refresh-profiles" variant="secondary" onClick={() => void refreshProfiles()}>
                <RefreshCcw className="mr-2 h-4 w-4" />
                刷新
              </Button>
            </CardHeader>
            <CardContent className="space-y-3">
              {profiles.length === 0 ? (
                <EmptyState title="还没有保存过配置" description="先到游戏库选择一个游戏，保存后会出现在这里。" />
              ) : (
                profiles.map((profile) => (
                  <button
                    key={profile.appid}
                    data-testid={`configured-profile-${profile.appid}`}
                    className="w-full rounded-xl border bg-white/[0.03] p-4 text-left transition hover:border-ring hover:bg-white/[0.05]"
                    onClick={() => openConfiguredProfile(profile)}
                    type="button"
                  >
                    <div className="flex items-start justify-between gap-4">
                      <div>
                        <div className="font-medium">{profile.name}</div>
                        <div className="mt-1 text-xs text-muted-foreground">AppID: {profile.appid}</div>
                      </div>
                      <ChevronRight className="h-4 w-4 text-muted-foreground" />
                    </div>
                    <div className="mt-3 grid gap-2 text-xs text-muted-foreground md:grid-cols-2">
                      <PathLine label="游戏目录" value={profile.game_dir} />
                      <PathLine label="目标程序" value={profile.target} />
                    </div>
                  </button>
                ))
              )}
            </CardContent>
          </Card>
        );
      case "logs":
        return (
          <Card>
            <CardHeader className="flex flex-row items-center justify-between gap-4 space-y-0">
              <div>
                <CardTitle>日志</CardTitle>
                <CardDescription>显示 logs 目录下最近的 Runner 日志，便于排查启动失败。</CardDescription>
              </div>
              <Button data-testid="refresh-logs" variant="secondary" onClick={() => void refreshLogs()}>
                <RefreshCcw className="mr-2 h-4 w-4" />
                刷新
              </Button>
            </CardHeader>
            <CardContent className="space-y-3">
              {logs.length === 0 ? (
                <EmptyState title="暂无日志" description="Runner 启动过游戏后，这里会显示日志文件。" />
              ) : (
                logs.map((log) => (
                  <div key={log.path} data-testid={`runner-log-${log.file_name}`} className="rounded-xl border bg-white/[0.03] p-4">
                    <div className="font-medium">{log.file_name}</div>
                    <div className="mt-1 break-all text-xs text-muted-foreground">{log.path}</div>
                    <pre className="mt-3 max-h-64 overflow-auto rounded-lg bg-black/30 p-3 text-xs text-muted-foreground">{log.content || "日志为空"}</pre>
                  </div>
                ))
              )}
            </CardContent>
          </Card>
        );
      case "settings":
        return (
          <Card data-testid="app-paths">
            <CardHeader className="flex flex-row items-center justify-between gap-4 space-y-0">
              <div>
                <CardTitle>设置</CardTitle>
                <CardDescription>查看稳定数据目录和 Steam 启动所需的 Runner 状态。</CardDescription>
              </div>
              <div className="flex flex-wrap gap-2">
                <Button data-testid="refresh-runner-status" variant="secondary" onClick={() => void refreshRunnerStatus()}>
                  <RefreshCcw className="mr-2 h-4 w-4" />
                  检查 Runner
                </Button>
                <Button data-testid="refresh-paths" variant="secondary" onClick={() => void refreshPaths()}>
                  <RefreshCcw className="mr-2 h-4 w-4" />
                  刷新路径
                </Button>
              </div>
            </CardHeader>
            <CardContent className="space-y-5">
              <section className="rounded-xl border bg-white/[0.03] p-4">
                <div className="flex flex-col gap-4 md:flex-row md:items-start md:justify-between">
                  <div className="space-y-2">
                    <div className="text-sm font-medium">SteamWrapper Runner</div>
                    <div data-testid="runner-status" className="text-sm text-muted-foreground">
                      Runner 状态：{runnerStatus?.healthy ? "已安装" : runnerStatus?.needs_install ? "未安装" : runnerStatus?.needs_update ? "需要更新" : "检查失败"}
                    </div>
                    <div data-testid="runner-path" className="break-all text-xs text-muted-foreground">
                      Runner 路径：{runnerStatus?.path ?? paths?.runner_path ?? "正在读取……"}
                    </div>
                    <div data-testid="runner-version" className="break-all text-xs text-muted-foreground">
                      随包摘要：{runnerStatus?.bundled_version?.slice(0, 12) ?? "未知"}
                      {runnerStatus?.installed_version ? ` · 已安装摘要：${runnerStatus.installed_version.slice(0, 12)}` : ""}
                    </div>
                    {runnerError && (
                      <div data-testid="runner-error" className="text-xs text-red-300">
                        {runnerError}
                      </div>
                    )}
                  </div>
                  {!runnerStatus?.healthy && (
                    <Button
                      data-testid={runnerStatus?.needs_install ? "runner-install" : "runner-repair"}
                      disabled={runnerBusy}
                      onClick={() => void installOrRepairRunner(runnerStatus?.needs_install ? "install_runner" : "repair_runner")}
                    >
                      <RefreshCcw className="mr-2 h-4 w-4" />
                      {runnerBusy ? "正在处理……" : runnerStatus?.needs_install ? "安装 Runner" : "重新安装 / 修复 Runner"}
                    </Button>
                  )}
                </div>
              </section>
              <div className="grid gap-3 md:grid-cols-2">
                {paths ? (
                  <>
                    <PathCard label="用户数据目录" value={paths.app_data_dir} />
                    <PathCard label="profiles.toml" value={paths.profiles_path} />
                    <PathCard label="Runner 稳定路径" value={paths.runner_path} />
                    <PathCard label="日志目录" value={paths.logs_dir} />
                    <PathCard label="备份目录" value={paths.backups_dir} />
                    <PathCard label="缓存目录" value={paths.cache_dir} />
                  </>
                ) : (
                  <EmptyState title="路径信息未加载" description="点击刷新重新读取。" />
                )}
              </div>
            </CardContent>
          </Card>
        );
      case "library":
      default:
        return (
          <>
            <section className="rounded-2xl border bg-card/70 p-5 shadow-xl shadow-black/10">
              <div className="flex flex-col gap-5 xl:flex-row xl:items-center xl:justify-between">
                <div className="space-y-2">
                  <div className="inline-flex w-fit items-center gap-2 rounded-full border bg-white/5 px-3 py-1 text-xs text-muted-foreground">
                    <Library className="h-3.5 w-3.5" />
                    本地扫描 · 不联网拉取封面
                  </div>
                  <h1 className="text-2xl font-semibold tracking-tight">游戏库</h1>
                  <p className="max-w-2xl text-sm text-muted-foreground">按照步骤完成配置；真正的配置表单会在点击游戏后悬浮打开。</p>
                </div>
                <div className="flex flex-wrap gap-3">
                  <Button data-testid="scan-games" onClick={scanLocalGames}>
                    扫描本地 Steam 游戏
                  </Button>
                  <Button data-testid="manual-add-game" variant="secondary" onClick={createManualGame}>
                    手动添加游戏
                  </Button>
                </div>
              </div>

              <div className="mt-5 grid gap-3 md:grid-cols-3">
                {guideSteps.map((step, index) => (
                  <div key={step.title} className="rounded-xl border bg-white/[0.03] p-4">
                    <div className="mb-3 flex h-7 w-7 items-center justify-center rounded-full bg-primary text-xs font-semibold text-primary-foreground">
                      {index + 1}
                    </div>
                    <div className="font-medium">{step.title}</div>
                    <div className="mt-1 text-sm text-muted-foreground">{step.description}</div>
                  </div>
                ))}
              </div>
            </section>

            <section className="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
              {games.length === 0 ? (
                <Card className="md:col-span-2 xl:col-span-3">
                  <CardHeader>
                    <CardTitle>还没有游戏列表</CardTitle>
                    <CardDescription>点击“扫描本地 Steam 游戏”开始。</CardDescription>
                  </CardHeader>
                </Card>
              ) : (
                games.map((game) => (
                  <Card
                    key={game.appid}
                    data-testid={`game-card-${game.appid}`}
                    className={cn(
                      "group cursor-pointer overflow-hidden transition hover:-translate-y-0.5 hover:border-ring hover:bg-white/[0.03]",
                      selectedGame?.appid === game.appid && "ring-1 ring-ring",
                    )}
                    onClick={() => openGameConfig(game)}
                  >
                    <div className="flex h-36 items-center justify-center bg-muted">
                      {game.cover_path ? (
                        <img src={convertFileSrc(game.cover_path)} alt={game.name} className="h-full w-full object-cover" />
                      ) : (
                        <div className="flex flex-col items-center gap-2 text-muted-foreground">
                          <ImageIcon className="h-8 w-8" />
                          <span className="text-xs">本地封面缓存未找到</span>
                        </div>
                      )}
                    </div>
                    <CardHeader>
                      <CardTitle className="flex items-start justify-between gap-3 text-base">
                        <span className="line-clamp-2">{game.name}</span>
                        <ChevronRight className="mt-0.5 h-4 w-4 shrink-0 text-muted-foreground transition group-hover:translate-x-0.5" />
                      </CardTitle>
                      <CardDescription>AppID: {game.appid}</CardDescription>
                    </CardHeader>
                    <CardContent>
                      <div className="flex items-start gap-2 text-sm text-muted-foreground">
                        <HardDrive className="mt-0.5 h-4 w-4 shrink-0" />
                        <span className="line-clamp-2">{game.install_dir ?? "未找到安装目录"}</span>
                      </div>
                    </CardContent>
                  </Card>
                ))
              )}
            </section>
          </>
        );
    }
  }

  return (
    <main data-testid="manager-root" className="flex h-screen overflow-hidden bg-background text-foreground">
      <aside
        className={cn(
          "hidden h-full shrink-0 flex-col border-r bg-slate-950/95 transition-[width] duration-200 lg:flex",
          sidebarCollapsed ? "w-[76px]" : "w-64",
        )}
      >
        <div className="flex h-12 items-center gap-3 border-b px-4">
          <img src={steamWrapperIcon} alt="SteamWrapper" className="h-8 w-8 rounded-lg" />
          {!sidebarCollapsed && (
            <div className="min-w-0">
              <div className="truncate text-sm font-semibold">SteamWrapper</div>
              <div className="text-[11px] text-muted-foreground">Manager v2</div>
            </div>
          )}
        </div>

        <nav className="flex-1 space-y-1 p-3">
          {navItems.map((item) => {
            const Icon = item.icon;
            const active = activeView === item.key;
            return (
              <button
                key={item.key}
                data-testid={`nav-${item.key}`}
                className={cn(
                  "flex h-10 w-full items-center gap-3 rounded-lg px-3 text-sm transition",
                  sidebarCollapsed && "justify-center px-0",
                  active ? "bg-secondary text-foreground" : "text-muted-foreground hover:bg-white/5 hover:text-foreground",
                )}
                title={sidebarCollapsed ? item.label : undefined}
                onClick={() => setActiveView(item.key)}
                type="button"
              >
                <Icon className="h-4 w-4 shrink-0" />
                {!sidebarCollapsed && <span>{item.label}</span>}
              </button>
            );
          })}
        </nav>

        <div className="border-t p-3">
          <button
            className={cn(
              "flex h-10 w-full items-center gap-3 rounded-lg px-3 text-sm text-muted-foreground transition hover:bg-white/5 hover:text-foreground",
              sidebarCollapsed && "justify-center px-0",
            )}
            onClick={() => setSidebarCollapsed((value) => !value)}
            type="button"
          >
            {sidebarCollapsed ? <PanelLeftOpen className="h-4 w-4" /> : <PanelLeftClose className="h-4 w-4" />}
            {!sidebarCollapsed && <span>折叠侧边栏</span>}
          </button>
        </div>
      </aside>

      <div className="flex min-w-0 flex-1 flex-col">
        <div data-tauri-drag-region className="flex h-12 shrink-0 select-none items-center border-b bg-slate-950/95 px-4 shadow-sm">
          <div data-tauri-drag-region className="flex flex-1 items-center gap-3 lg:hidden">
            <img src={steamWrapperIcon} alt="SteamWrapper" className="h-7 w-7 rounded-lg" />
            <div data-tauri-drag-region>
              <div className="text-sm font-semibold leading-none">SteamWrapper Manager</div>
              <div className="mt-0.5 text-[11px] text-muted-foreground">配置一次，以后从 Steam 正常启动</div>
            </div>
          </div>
          <div data-testid="status-text" data-tauri-drag-region className="hidden flex-1 text-xs text-muted-foreground lg:block">
            {statusText}
          </div>
          <div className="flex items-center gap-1">
            <WindowButton label="最小化" onClick={() => void getCurrentWindow().minimize()}>
              <Minus className="h-4 w-4" />
            </WindowButton>
            <WindowButton label="最大化或还原" onClick={() => void getCurrentWindow().toggleMaximize()}>
              <Square className="h-3.5 w-3.5" />
            </WindowButton>
            <WindowButton label="关闭" danger onClick={() => void getCurrentWindow().close()}>
              <X className="h-4 w-4" />
            </WindowButton>
          </div>
        </div>

        <div className="min-h-0 flex-1 overflow-y-auto">
          <div className="mx-auto max-w-7xl space-y-6 p-6">{renderContent()}</div>
        </div>
      </div>

      {isConfigOpen && selectedGame && (
        <div data-testid="config-dialog" className="fixed inset-0 z-50 flex items-center justify-center bg-black/70 p-6 backdrop-blur-sm">
          <Card className="w-full max-w-2xl border-white/10 bg-slate-950 shadow-2xl shadow-black/50">
            <CardHeader className="flex flex-row items-start justify-between gap-4 space-y-0">
              <div>
                <CardTitle>配置启动目标</CardTitle>
                <CardDescription className="mt-2">
                  {selectedGame.name} · AppID {selectedGame.appid}
                </CardDescription>
              </div>
              <button
                className="rounded-md p-2 text-muted-foreground transition hover:bg-white/10 hover:text-foreground"
                onClick={() => setConfigOpen(false)}
                type="button"
              >
                <X className="h-4 w-4" />
              </button>
            </CardHeader>
            <CardContent className="space-y-4">
              <div className="rounded-lg border bg-white/[0.03] p-3 text-sm text-muted-foreground">
                <div className="font-medium text-foreground">游戏目录</div>
                <div className="mt-1 break-all">{selectedGame.install_dir ?? "未找到安装目录"}</div>
              </div>

              <label className="block space-y-2">
                <span className="text-sm font-medium">真正要启动的程序</span>
                <div className="flex gap-2">
                  <input
                    data-testid="target-path"
                    className="h-10 min-w-0 flex-1 rounded-md border bg-background px-3 text-sm outline-none focus:ring-1 focus:ring-ring"
                    value={targetPath}
                    onChange={(event) => setTargetPath(event.target.value)}
                    placeholder="例如 Game_CHS.exe 或 launcher.exe"
                  />
                  <Button data-testid="choose-target" variant="secondary" onClick={() => void chooseTargetPath()} type="button">
                    <FolderOpen className="mr-2 h-4 w-4" />
                    浏览
                  </Button>
                </div>
              </label>

              <div className="flex flex-wrap gap-3">
                <Button data-testid="save-profile" onClick={saveCurrentProfile}>
                  <Save className="mr-2 h-4 w-4" />
                  保存并生成启动选项
                </Button>
                <Button variant="secondary" onClick={() => generateLaunchOption(selectedGame.appid)}>
                  <Copy className="mr-2 h-4 w-4" />
                  仅生成启动选项
                </Button>
                <Button variant="outline" onClick={() => setStatusText("测试启动稍后实现")}>
                  <Play className="mr-2 h-4 w-4" />
                  测试启动
                </Button>
              </div>

              <label className="space-y-2 block">
                <span className="text-sm font-medium">Launch Options</span>
                <textarea
                  data-testid="launch-option"
                  className="min-h-28 w-full rounded-md border bg-background p-3 font-mono text-xs outline-none focus:ring-1 focus:ring-ring"
                  value={launchOption}
                  onChange={(event) => setLaunchOption(event.target.value)}
                  placeholder="保存配置后生成"
                />
              </label>

              <div data-testid="status-text" className="text-xs text-muted-foreground">{statusText}</div>
            </CardContent>
          </Card>
        </div>
      )}
    </main>
  );
}

function EmptyState({ title, description }: { title: string; description: string }) {
  return (
    <div className="rounded-xl border bg-white/[0.03] p-8 text-sm text-muted-foreground">
      <div className="font-medium text-foreground">{title}</div>
      <div className="mt-1">{description}</div>
    </div>
  );
}

function PathLine({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <div className="text-[11px] text-muted-foreground/80">{label}</div>
      <div className="mt-1 break-all">{value}</div>
    </div>
  );
}

function PathCard({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-xl border bg-white/[0.03] p-4 text-sm">
      <div className="font-medium">{label}</div>
      <div className="mt-2 break-all text-muted-foreground">{value}</div>
    </div>
  );
}

function WindowButton({
  label,
  danger = false,
  onClick,
  children,
}: {
  label: string;
  danger?: boolean;
  onClick: () => void;
  children: React.ReactNode;
}) {
  return (
    <button
      className={cn(
        "inline-flex h-8 w-8 items-center justify-center rounded-md text-muted-foreground transition hover:bg-white/10 hover:text-foreground",
        danger && "hover:bg-red-500/80 hover:text-white",
      )}
      aria-label={label}
      onClick={onClick}
      type="button"
    >
      {children}
    </button>
  );
}
