use anyhow::Context;
use std::{
    ffi::c_void,
    os::windows::{io::AsRawHandle, process::CommandExt},
    process::{Command, ExitStatus},
    ptr::NonNull,
};
use windows::Win32::{
    Foundation::{CloseHandle, HANDLE, INVALID_HANDLE_VALUE},
    System::{
        JobObjects::{
            AssignProcessToJobObject, CreateJobObjectW,
            JobObjectAssociateCompletionPortInformation, SetInformationJobObject,
            JOBOBJECT_ASSOCIATE_COMPLETION_PORT,
        },
        SystemServices::JOB_OBJECT_MSG_ACTIVE_PROCESS_ZERO,
        Threading::{ResumeThread, CREATE_NO_WINDOW, CREATE_SUSPENDED, INFINITE},
        IO::{CreateIoCompletionPort, GetQueuedCompletionStatus, OVERLAPPED},
    },
};

pub(super) fn prepare_command(command: &mut Command) {
    command.creation_flags(CREATE_NO_WINDOW.0);
}

pub(super) fn launch_job(mut command: Command) -> anyhow::Result<ExitStatus> {
    command.creation_flags(CREATE_NO_WINDOW.0 | CREATE_SUSPENDED.0);
    let mut child = command
        .spawn()
        .context("failed to start Job Object target")?;
    let mut suspended_child = SuspendedChildGuard::new(&mut child);
    let process_handle = HANDLE(child.as_raw_handle());

    let job = unsafe { CreateJobObjectW(None, None) }.context("failed to create Job Object")?;
    let completion_port = unsafe { CreateIoCompletionPort(INVALID_HANDLE_VALUE, None, 0, 1) }
        .context("failed to create Job Object completion port")?;
    let handles = JobHandles {
        job,
        completion_port,
    };
    let association = JOBOBJECT_ASSOCIATE_COMPLETION_PORT {
        CompletionKey: job.0,
        CompletionPort: completion_port,
    };

    unsafe {
        SetInformationJobObject(
            job,
            JobObjectAssociateCompletionPortInformation,
            &association as *const _ as *const c_void,
            u32::try_from(std::mem::size_of_val(&association))
                .expect("completion-port association size fits u32"),
        )
    }
    .context("failed to associate Job Object completion port")?;
    unsafe { AssignProcessToJobObject(job, process_handle) }
        .context("failed to assign target to Job Object")?;
    resume_main_thread(&child)?;
    suspended_child.disarm();

    let launcher_status = child.wait();
    let job_status = wait_for_job_empty(handles.completion_port);
    match (launcher_status, job_status) {
        (Ok(status), Ok(())) => Ok(status),
        (Err(err), Ok(())) => Err(err).context("failed while waiting for Job Object launcher"),
        (Ok(_), Err(err)) => Err(err),
        (Err(launcher_err), Err(job_err)) => Err(job_err).context(format!(
            "failed while waiting for Job Object launcher: {launcher_err}"
        )),
    }
}

fn resume_main_thread(child: &std::process::Child) -> anyhow::Result<()> {
    let thread_handle = unsafe {
        windows::Win32::System::Threading::OpenThread(
            windows::Win32::System::Threading::THREAD_SUSPEND_RESUME,
            false,
            main_thread_id(child.id())?,
        )
    }
    .context("failed to open suspended target thread")?;
    let result = unsafe { ResumeThread(thread_handle) };
    unsafe { CloseHandle(thread_handle) }.ok();
    if result == u32::MAX {
        anyhow::bail!("failed to resume Job Object target thread")
    }
    Ok(())
}

fn main_thread_id(process_id: u32) -> anyhow::Result<u32> {
    use windows::Win32::System::Diagnostics::ToolHelp::{
        CreateToolhelp32Snapshot, Thread32First, Thread32Next, TH32CS_SNAPTHREAD, THREADENTRY32,
    };

    let snapshot = unsafe { CreateToolhelp32Snapshot(TH32CS_SNAPTHREAD, 0) }
        .context("failed to snapshot target threads")?;
    let snapshot_handle = SnapshotHandle(snapshot);
    let mut entry = THREADENTRY32 {
        dwSize: u32::try_from(std::mem::size_of::<THREADENTRY32>())
            .expect("thread entry size fits u32"),
        ..Default::default()
    };
    unsafe { Thread32First(snapshot_handle.0, &mut entry) }
        .context("failed to enumerate target threads")?;
    loop {
        if entry.th32OwnerProcessID == process_id {
            return Ok(entry.th32ThreadID);
        }
        if unsafe { Thread32Next(snapshot_handle.0, &mut entry) }.is_err() {
            anyhow::bail!("could not find the suspended target thread")
        }
    }
}

fn wait_for_job_empty(completion_port: HANDLE) -> anyhow::Result<()> {
    loop {
        let mut message = 0;
        let mut completion_key = 0usize;
        let mut overlapped: *mut OVERLAPPED = std::ptr::null_mut();
        let result = unsafe {
            GetQueuedCompletionStatus(
                completion_port,
                &mut message,
                &mut completion_key,
                &mut overlapped,
                INFINITE,
            )
        };
        if result.is_err() && overlapped.is_null() {
            return Err(result.expect_err("failed completion status has an error"))
                .context("failed while waiting for Job Object completion");
        }
        // Process-create/exit notifications are informational. Only this message
        // proves that every process assigned to the Job has exited.
        if message == JOB_OBJECT_MSG_ACTIVE_PROCESS_ZERO {
            return Ok(());
        }
    }
}

struct JobHandles {
    job: HANDLE,
    completion_port: HANDLE,
}

impl Drop for JobHandles {
    fn drop(&mut self) {
        unsafe { CloseHandle(self.completion_port) }.ok();
        unsafe { CloseHandle(self.job) }.ok();
    }
}

struct SnapshotHandle(HANDLE);

impl Drop for SnapshotHandle {
    fn drop(&mut self) {
        unsafe { CloseHandle(self.0) }.ok();
    }
}

struct SuspendedChildGuard {
    child: NonNull<std::process::Child>,
    armed: bool,
}

impl SuspendedChildGuard {
    fn new(child: &mut std::process::Child) -> Self {
        Self {
            child: NonNull::from(child),
            armed: true,
        }
    }

    fn disarm(&mut self) {
        self.armed = false;
    }
}

impl Drop for SuspendedChildGuard {
    fn drop(&mut self) {
        if self.armed {
            // SAFETY: the guard never outlives the local `Child` it was created from.
            let child = unsafe { self.child.as_mut() };
            let _ = child.kill();
            let _ = child.wait();
        }
    }
}
