use crate::project::ProjectState;

#[derive(Debug, Default)]
pub struct EngineHandle {
    pub project: ProjectState,
}

impl EngineHandle {
    pub fn new() -> Self {
        Self {
            project: ProjectState::default(),
        }
    }
}
