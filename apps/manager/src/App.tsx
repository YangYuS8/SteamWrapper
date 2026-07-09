import { convertFileSrc, invoke } from "@tauri-apps/api/core";
import { getCurrentWindow } from "@tauri-apps/api/window";
import {
  ChevronRight,
  Copy,
  HardDrive,
  ImageIcon,
  Library,
  ListChecks,
  Minus,
  PanelLeftClose,
  PanelLeftOpen,
  Play,
  Save,
  ScrollText,
  Settings2,
  Square,
  X,
} from "lucide-react";
import { useState } from "react";
import steamWrapperIcon from "@/assets/steamwrapper.svg";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { cn } from "@/lib/utils";

const appWindow = getCurrentWindow();

type LocalSteamGame = {
  appid: string;
  name: string;
  install_dir?: string;
  cover_path?: string;
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

export function App() {
  const [games, setGames] = useState<LocalSteamGame[]>([]);
  const [selectedGame, setSelectedGame] = useState<LocalSteamGame | null>(null);
  const [targetPath, setTargetPath] = useState("");
  const [launchOption, setLaunchOption] = useState("");
  const [statusText, setStatusText] = useState("准备就绪");
  const [activeView, setActiveView] = useState<ViewKey>("library");
  const [sidebarCollapsed, setSidebarCollapsed] = useState(false);
  const [isConfigOpen, setConfigOpen] = useState(false);

  async function generateLaunchOption(appid: string) {
    const option = await invoke<string>("generate_launch_option", { appid });
    setLaunchOption(option);
    setStatusText("已生成启动选项");
  }

  async function scanLocalGames() {
    setStatusText("正在扫描本地 Steam 游戏库……");
    const scanned = await invoke<LocalSteamGame[]>("scan_local_steam_games_command");
    setGames(scanned);
    setStatusText(scanned.length > 0 ? `已找到 ${scanned.length} 个本地 Steam 游戏` : "没有扫描到本地 Steam 游戏");
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

    await invoke("save_profile", {
      request: {
        appid: selectedGame.appid,
        name: selectedGame.name,
        game_dir: selectedGame.install_dir,
        target: targetPath.trim(),
      },
    });

    await generateLaunchOption(selectedGame.appid);
    setStatusText("配置已保存");
  }

  function renderContent() {
    switch (activeView) {
      case "configured":
        return <PlaceholderView title="已配置游戏" description="保存过的 profile 会在后续版本集中展示、编辑和恢复。" />;
      case "logs":
        return <PlaceholderView title="日志" description="后续会在这里查看 Runner 最近一次启动记录和错误信息。" />;
      case "settings":
        return <PlaceholderView title="设置" description="稳定 Runner 路径、备份目录和高级选项会放在这里。" />;
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
                  <Button onClick={scanLocalGames}>扫描本地 Steam 游戏</Button>
                  <Button variant="secondary" onClick={() => setStatusText("手动添加游戏稍后实现")}>
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
    <main className="flex h-screen overflow-hidden bg-background text-foreground">
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
          <div data-tauri-drag-region className="hidden flex-1 text-xs text-muted-foreground lg:block">
            {statusText}
          </div>
          <div className="flex items-center gap-1">
            <WindowButton label="最小化" onClick={() => void appWindow.minimize()}>
              <Minus className="h-4 w-4" />
            </WindowButton>
            <WindowButton label="最大化或还原" onClick={() => void appWindow.toggleMaximize()}>
              <Square className="h-3.5 w-3.5" />
            </WindowButton>
            <WindowButton label="关闭" danger onClick={() => void appWindow.close()}>
              <X className="h-4 w-4" />
            </WindowButton>
          </div>
        </div>

        <div className="min-h-0 flex-1 overflow-y-auto">
          <div className="mx-auto max-w-7xl space-y-6 p-6">{renderContent()}</div>
        </div>
      </div>

      {isConfigOpen && selectedGame && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/70 p-6 backdrop-blur-sm">
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

              <label className="space-y-2 block">
                <span className="text-sm font-medium">真正要启动的程序</span>
                <input
                  className="h-10 w-full rounded-md border bg-background px-3 text-sm outline-none focus:ring-1 focus:ring-ring"
                  value={targetPath}
                  onChange={(event) => setTargetPath(event.target.value)}
                  placeholder="例如 Game_CHS.exe 或 launcher.exe"
                />
              </label>

              <div className="flex flex-wrap gap-3">
                <Button onClick={saveCurrentProfile}>
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
                  className="min-h-28 w-full rounded-md border bg-background p-3 font-mono text-xs outline-none focus:ring-1 focus:ring-ring"
                  value={launchOption}
                  onChange={(event) => setLaunchOption(event.target.value)}
                  placeholder="保存配置后生成"
                />
              </label>

              <div className="text-xs text-muted-foreground">{statusText}</div>
            </CardContent>
          </Card>
        </div>
      )}
    </main>
  );
}

function PlaceholderView({ title, description }: { title: string; description: string }) {
  return (
    <Card>
      <CardHeader>
        <CardTitle>{title}</CardTitle>
        <CardDescription>{description}</CardDescription>
      </CardHeader>
      <CardContent>
        <div className="rounded-xl border bg-white/[0.03] p-8 text-sm text-muted-foreground">该页面的完整功能将在后续迭代开放。</div>
      </CardContent>
    </Card>
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
