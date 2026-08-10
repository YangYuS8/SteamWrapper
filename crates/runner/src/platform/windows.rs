use process_wrap::std::{CommandWrap, CreationFlags, JobObject};
use std::{
    os::windows::process::CommandExt,
    process::{Command, ExitStatus},
};
use windows::Win32::System::Threading::{CREATE_NO_WINDOW, PROCESS_CREATION_FLAGS};

pub(super) fn prepare_command(command: &mut Command) {
    command.creation_flags(CREATE_NO_WINDOW.0);
}

pub(super) fn launch_job(command: Command) -> anyhow::Result<ExitStatus> {
    let mut command = CommandWrap::from(command);
    command.wrap(CreationFlags(PROCESS_CREATION_FLAGS(CREATE_NO_WINDOW.0)));
    command.wrap(JobObject);
    let mut child = command.spawn()?;
    Ok(child.wait()?)
}
