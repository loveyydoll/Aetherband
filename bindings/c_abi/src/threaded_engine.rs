//! Keep engine/device lifecycle and decoder work serialized on one Rust control
//! thread, away from Flutter's UI isolate. Only owned commands and Send results
//! cross this bounded control-side queue; CPAL's Send support is not required.
//! None of this channel, allocation or waiting runs on the audio callback.

use std::path::Path;
use std::sync::mpsc::{self, SyncSender};
use std::thread::{self, JoinHandle};

use daw_core::device::{DeviceError, DeviceInfo};
use daw_core::ringbuf::{TelemetryFrame, TrackId};
use daw_core::TrackInfo;

type Job<T> = Box<dyn FnOnce(&mut T) + Send>;

pub(super) struct ControlThread<T> {
    sender: Option<SyncSender<Job<T>>>,
    worker: Option<JoinHandle<()>>,
}

impl<T: 'static> ControlThread<T> {
    fn spawn(create: impl FnOnce() -> Result<T, ()> + Send + 'static) -> Result<Self, ()> {
        let (sender, jobs) = mpsc::sync_channel::<Job<T>>(64);
        let (ready, initialization) = mpsc::sync_channel(1);
        let worker = thread::Builder::new()
            .name("aetherband-engine-control".into())
            .spawn(move || {
                let Ok(mut engine) = create() else {
                    let _ = ready.send(false);
                    return;
                };
                if ready.send(true).is_err() {
                    return;
                }
                while let Ok(job) = jobs.recv() {
                    job(&mut engine);
                }
                // The engine and its stream are destroyed here, on the same
                // OS thread that created and operated them.
            })
            .map_err(|_| ())?;
        if initialization.recv() != Ok(true) {
            drop(sender);
            let _ = worker.join();
            return Err(());
        }
        Ok(Self {
            sender: Some(sender),
            worker: Some(worker),
        })
    }

    fn call<R: Send + 'static>(
        &self,
        operation: impl FnOnce(&mut T) -> R + Send + 'static,
    ) -> Result<R, ()> {
        let (result, response) = mpsc::sync_channel(1);
        self.sender
            .as_ref()
            .ok_or(())?
            .try_send(Box::new(move |engine| {
                let _ = result.send(operation(engine));
            }))
            .map_err(|_| ())?;
        response.recv().map_err(|_| ())
    }
}

impl<T> Drop for ControlThread<T> {
    fn drop(&mut self) {
        // Closing the only sender drains accepted commands, then destroys the
        // engine. The worker never owns this wrapper, so cannot join itself.
        self.sender.take();
        if let Some(worker) = self.worker.take() {
            let _ = worker.join();
        }
    }
}

pub(super) type EngineHandle = ControlThread<daw_core::DAWEngine>;

macro_rules! command {
    ($name:ident $(, $arg:ident : $ty:ty)*) => {
        pub fn $name(&self, $($arg: $ty),*) -> bool {
            self.call(move |engine| engine.$name($($arg),*)).unwrap_or(false)
        }
    };
}

impl EngineHandle {
    pub fn new() -> Result<Self, ()> {
        Self::spawn(|| daw_core::DAWEngine::new().map_err(|_| ()))
    }

    command!(play);
    command!(pause);
    command!(stop);
    pub fn seek_seconds(&self, seconds: f64) -> bool {
        self.call(move |engine| {
            if !seconds.is_finite() || seconds < 0.0 {
                return false;
            }
            let frame = seconds * engine.output_sample_rate() as f64;
            if !frame.is_finite() || frame > i64::MAX as f64 {
                return false;
            }
            engine.seek(frame.round() as i64)
        })
        .unwrap_or(false)
    }
    command!(synth_event, event: u32, key: u32, value: f32);
    pub fn set_sequence_region(
        &self,
        id: u32,
        start_seconds: f64,
        notes: [Option<u8>; 16],
    ) -> bool {
        self.call(move |engine| engine.set_sequence_region(id, start_seconds, notes))
            .unwrap_or(false)
    }
    command!(remove_sequence_region, id: u32);
    command!(configure_transport, bpm: f32, beats_per_bar: u8, metronome: bool, sequence: bool);
    command!(set_master_volume, gain: f32);
    pub fn export_wav(&self, path: &Path) -> Result<(), ()> {
        let path = path.to_owned();
        self.call(move |engine| engine.export_mixdown(&path).map_err(|_| ()))?
    }
    pub fn start_recording(&self, path: &Path) -> Result<u32, ()> {
        let path = path.to_owned();
        self.call(move |engine| engine.start_recording(&path).map_err(|_| ()))?
    }
    pub fn stop_recording(&self) -> Result<daw_core::device::RecordingStats, ()> {
        self.call(|engine| engine.stop_recording().map_err(|_| ()))?
    }
    command!(set_test_tone, enabled: bool, frequency: f32);
    command!(remove_track, id: TrackId);
    command!(set_track_volume, id: TrackId, gain: f32);
    command!(set_track_pan, id: TrackId, pan: f32);
    command!(set_track_start_seconds, id: TrackId, seconds: f64);
    command!(set_track_region_seconds, id: TrackId, source_start: f64, duration: f64);
    command!(mute_track, id: TrackId, muted: bool);
    command!(solo_track, id: TrackId, solo: bool);

    pub fn enumerate_devices(&self) -> Result<Vec<DeviceInfo>, DeviceError> {
        self.call(|engine| engine.enumerate_devices())
            .map_err(|_| DeviceError::NoHostAvailable)?
    }

    pub fn select_device(&self, index: usize) -> Result<(), ()> {
        self.call(move |engine| engine.select_device(index).map_err(|_| ()))?
    }

    pub fn output_sample_rate(&self) -> Result<u32, ()> {
        self.call(|engine| engine.output_sample_rate())
    }

    pub fn poll_telemetry(&self) -> Result<Option<TelemetryFrame>, ()> {
        self.call(|engine| engine.poll_telemetry())
    }

    pub fn load_track(&self, path: &Path) -> Result<TrackId, ()> {
        let path = path.to_owned();
        self.call(move |engine| engine.load_track(&path).map_err(|_| ()))?
    }

    pub fn tracks(&self) -> Result<Vec<TrackInfo>, ()> {
        self.call(|engine| engine.tracks().to_vec())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::cell::Cell;
    use std::rc::Rc;

    struct LocalState {
        value: Rc<Cell<u32>>,
        destroyed: mpsc::Sender<thread::ThreadId>,
    }

    impl Drop for LocalState {
        fn drop(&mut self) {
            let _ = self.destroyed.send(thread::current().id());
        }
    }

    #[test]
    fn non_send_state_stays_on_its_owner_thread_across_callers_and_shutdown() {
        let (destroyed, destruction) = mpsc::channel();
        let owner = ControlThread::spawn(move || {
            Ok(LocalState {
                value: Rc::new(Cell::new(0)),
                destroyed,
            })
        })
        .unwrap();
        let original_thread = owner.call(|_| thread::current().id()).unwrap();
        assert_ne!(original_thread, thread::current().id());
        thread::spawn(move || {
            assert_eq!(
                owner.call(|state| {
                    state.value.set(42);
                    thread::current().id()
                }),
                Ok(original_thread)
            );
            assert_eq!(owner.call(|state| state.value.get()), Ok(42));
            drop(owner);
        })
        .join()
        .unwrap();
        assert_eq!(destruction.recv().unwrap(), original_thread);
    }

    #[test]
    fn initialization_failure_is_reported_and_joined() {
        assert!(ControlThread::<()>::spawn(|| Err(())).is_err());
    }
}
