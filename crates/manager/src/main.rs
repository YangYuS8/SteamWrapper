use eframe::egui;
use steamwrapper_core::build_launch_option;

fn main() -> eframe::Result<()> {
    let options = eframe::NativeOptions::default();
    eframe::run_native(
        "SteamWrapper Manager",
        options,
        Box::new(|_cc| Ok(Box::<ManagerApp>::default())),
    )
}

struct ManagerApp {
    runner_path: String,
    appid: String,
    generated_launch_option: String,
}

impl Default for ManagerApp {
    fn default() -> Self {
        Self {
            runner_path: String::from(r"C:\Users\<User>\AppData\Local\SteamWrapper\SteamWrapperRunner.exe"),
            appid: String::from("123456"),
            generated_launch_option: String::new(),
        }
    }
}

impl eframe::App for ManagerApp {
    fn update(&mut self, ctx: &egui::Context, _frame: &mut eframe::Frame) {
        egui::CentralPanel::default().show(ctx, |ui| {
            ui.heading("SteamWrapper Manager v2");
            ui.label("This is the initial GUI skeleton. The final Manager will configure profiles and apply Steam Launch Options.");

            ui.separator();
            ui.label("Runner path");
            ui.text_edit_singleline(&mut self.runner_path);

            ui.label("Steam AppID");
            ui.text_edit_singleline(&mut self.appid);

            if ui.button("Generate Launch Options").clicked() {
                self.generated_launch_option = build_launch_option(&self.runner_path, &self.appid);
            }

            ui.label("Generated Launch Options");
            ui.add(
                egui::TextEdit::multiline(&mut self.generated_launch_option)
                    .desired_rows(3)
                    .code_editor(),
            );
        });
    }
}
