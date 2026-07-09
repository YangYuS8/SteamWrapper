import { convertFileSrc, invoke } from "@tauri-apps/api/core";
import { HardDrive, ImageIcon, Play, Save, Settings2, ShieldCheck } from "lucide-react";
import { useState } from "react";
import steamWrapperIcon from "@/assets/steamwrapper.svg";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";

type LocalSteamGame = {
  appid: string;
  name: string;
  install_dir?: string;
  cover_path?: string;
};

export function App() {
  const [games, setGames] = useState<LocalSteamGame[]>([]);
  const [selectedGame, setSelectedGame] = useState<LocalSteamGame | null>(null);
  const [targetPath, setTargetPath] = useState("");
  const [launchOption, setLaunchOption] = useState("");
  const [statusText, setStatusText] = useState("点击“扫描本地 Steam 游戏”开始。第一阶段不会联网拉取封面。");

  async function generateLaunchOption(appid: string) {
    const option = await invoke<string>("generate_launch_option", { appid });
    setLaunchOption(option);
    setStatusText("已生成启动选项。后续版本会支持一键应用到 Steam。");
  }

  async function scanLocalGames() {
    setStatusText("正在扫描本地 Steam 游戏库……");
    const scanned = await invoke<LocalSteamGame[]>("scan_local_steam_games_command");
    setGames(scanned);
    setSelectedGame(scanned[0] ?? null);
    setStatusText(scanned.length > 0 ? `已找到 ${scanned.length} 个本地 Steam 游戏。` : "没有扫描到本地 Steam 游戏。可以稍后手动添加。");
  }

  async function saveCurrentProfile() {
    if (!selectedGame) {
      setStatusText("请先选择一个游戏。");
      return;
    }

    if (!selectedGame.install_dir) {
      setStatusText("当前游戏缺少安装目录，暂时无法保存配置。");
      return;
    }

    if (!targetPath.trim()) {
      setStatusText("请填写真正要启动的 exe 或 launcher 路径，可以是相对游戏目录的路径。");
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
    setStatusText("配置已保存到 profiles.toml，并生成了启动选项。");
  }

  return (
    <main className="min-h-screen bg-background text-foreground">
      <div className="mx-auto flex max-w-7xl gap-6 p-6">
        <aside className="hidden w-64 shrink-0 flex-col gap-3 rounded-2xl border bg-card p-4 lg:flex">
          <div className="flex items-center gap-3 px-2 py-1">
            <img src={steamWrapperIcon} alt="SteamWrapper" className="h-11 w-11 rounded-xl" />
            <div>
              <div className="font-semibold">SteamWrapper</div>
              <div className="text-xs text-muted-foreground">Manager v2</div>
            </div>
          </div>
          <nav className="mt-4 space-y-1 text-sm">
            <div className="rounded-lg bg-secondary px-3 py-2 font-medium">游戏库</div>
            <div className="px-3 py-2 text-muted-foreground">已配置游戏</div>
            <div className="px-3 py-2 text-muted-foreground">日志</div>
            <div className="px-3 py-2 text-muted-foreground">设置</div>
          </nav>
        </aside>

        <section className="min-w-0 flex-1 space-y-6">
          <Card className="overflow-hidden border-none bg-gradient-to-br from-slate-900 to-slate-700 text-white shadow-xl">
            <CardHeader className="space-y-4 p-8">
              <div className="inline-flex w-fit items-center gap-2 rounded-full bg-white/10 px-3 py-1 text-xs text-white/80">
                <ShieldCheck className="h-3.5 w-3.5" />
                不需要 SteamEdit，不复制到每个游戏目录
              </div>
              <div className="flex flex-col gap-5 md:flex-row md:items-center md:justify-between">
                <div className="space-y-2">
                  <CardTitle className="text-3xl">配置一次，以后从 Steam 正常启动</CardTitle>
                  <CardDescription className="max-w-2xl text-white/70">
                    Manager 只负责配置。日常启动时，Steam 会自动调用无界面的 Runner，然后启动你选择的汉化 exe、启动器或 mod loader。
                  </CardDescription>
                </div>
                <img src={steamWrapperIcon} alt="SteamWrapper" className="hidden h-24 w-24 shrink-0 rounded-3xl md:block" />
              </div>
              <div className="flex flex-wrap gap-3">
                <Button onClick={scanLocalGames}>扫描本地 Steam 游戏</Button>
                <Button variant="secondary">手动添加游戏</Button>
              </div>
            </CardHeader>
          </Card>

          <div className="grid gap-6 xl:grid-cols-[1fr_380px]">
            <div className="grid gap-4 md:grid-cols-2">
              {games.length === 0 ? (
                <Card className="md:col-span-2">
                  <CardHeader>
                    <CardTitle>还没有游戏列表</CardTitle>
                    <CardDescription>{statusText}</CardDescription>
                  </CardHeader>
                </Card>
              ) : (
                games.map((game) => (
                  <Card key={game.appid} className={`overflow-hidden ${selectedGame?.appid === game.appid ? "ring-1 ring-ring" : ""}`}>
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
                      <CardTitle className="text-lg">{game.name}</CardTitle>
                      <CardDescription>AppID: {game.appid}</CardDescription>
                    </CardHeader>
                    <CardContent className="space-y-4">
                      <div className="flex items-start gap-2 text-sm text-muted-foreground">
                        <HardDrive className="mt-0.5 h-4 w-4 shrink-0" />
                        <span className="line-clamp-2">{game.install_dir ?? "未找到安装目录"}</span>
                      </div>
                      <div className="flex gap-2">
                        <Button
                          size="sm"
                          onClick={() => {
                            setSelectedGame(game);
                            setTargetPath("");
                            setStatusText(`已选择：${game.name}`);
                          }}
                        >
                          配置
                        </Button>
                        <Button size="sm" variant="outline" onClick={() => generateLaunchOption(game.appid)}>
                          生成启动选项
                        </Button>
                      </div>
                    </CardContent>
                  </Card>
                ))
              )}
            </div>

            <Card className="h-fit">
              <CardHeader>
                <CardTitle className="flex items-center gap-2">
                  <Settings2 className="h-5 w-5" />
                  当前配置状态
                </CardTitle>
                <CardDescription>{statusText}</CardDescription>
              </CardHeader>
              <CardContent className="space-y-4">
                <div className="rounded-lg border bg-muted/40 p-3 text-sm text-muted-foreground">
                  第一阶段只读取本地 Steam 游戏库和本地封面缓存，不接入在线封面服务。
                </div>

                <div className="space-y-2">
                  <div className="text-sm font-medium">当前游戏</div>
                  <div className="rounded-md border bg-muted/30 p-3 text-sm text-muted-foreground">
                    {selectedGame ? `${selectedGame.name} (${selectedGame.appid})` : "未选择游戏"}
                  </div>
                </div>

                <div className="space-y-2">
                  <div className="text-sm font-medium">真正要启动的程序</div>
                  <input
                    className="h-9 w-full rounded-md border bg-background px-3 text-sm outline-none focus:ring-1 focus:ring-ring"
                    value={targetPath}
                    onChange={(event) => setTargetPath(event.target.value)}
                    placeholder="例如 Game_CHS.exe 或 launcher.exe"
                  />
                </div>

                <Button className="w-full" onClick={saveCurrentProfile}>
                  <Save className="mr-2 h-4 w-4" />
                  保存配置并生成启动选项
                </Button>

                <div className="space-y-2">
                  <div className="text-sm font-medium">生成的 Launch Options</div>
                  <textarea
                    className="min-h-28 w-full rounded-md border bg-background p-3 font-mono text-xs outline-none focus:ring-1 focus:ring-ring"
                    value={launchOption}
                    onChange={(event) => setLaunchOption(event.target.value)}
                    placeholder="选择游戏后生成启动选项"
                  />
                </div>
                <Button className="w-full" variant="secondary">
                  <Play className="mr-2 h-4 w-4" />
                  测试启动，稍后实现
                </Button>
              </CardContent>
            </Card>
          </div>
        </section>
      </div>
    </main>
  );
}
