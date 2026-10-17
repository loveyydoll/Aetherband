//! Typed, control-thread audio graph model.
//!
//! This module intentionally models and validates graphs only. It is not yet
//! executed by the real-time callback. Graph compilation and runtime swapping
//! will be added only after transport and track playback are verified end to end.
//!
//! Invariants:
//! - graph editing/validation happens off the audio callback;
//! - ports have explicit signal kinds;
//! - node IDs are stable within a graph;
//! - a graph must validate before it can be compiled into a runtime.

use std::collections::HashMap;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub struct NodeId(pub u64);

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum SignalKind {
    Audio,
    Control,
    Event,
    Analysis,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Port {
    pub name: String,
    pub kind: SignalKind,
    pub channels: u16,
}

impl Port {
    pub fn new(name: impl Into<String>, kind: SignalKind, channels: u16) -> Self {
        Self { name: name.into(), kind, channels }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NodeSpec {
    pub id: NodeId,
    pub name: String,
    pub inputs: Vec<Port>,
    pub outputs: Vec<Port>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct Connection {
    pub from_node: NodeId,
    pub from_port: usize,
    pub to_node: NodeId,
    pub to_port: usize,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum GraphError {
    DuplicateNode(NodeId),
    MissingNode(NodeId),
    InvalidOutputPort { node: NodeId, port: usize },
    InvalidInputPort { node: NodeId, port: usize },
    IncompatiblePorts { from: NodeId, to: NodeId },
    DuplicateConnection(Connection),
    CycleDetected,
}

#[derive(Debug, Clone, Default)]
pub struct AudioGraph {
    nodes: Vec<NodeSpec>,
    connections: Vec<Connection>,
}

impl AudioGraph {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn nodes(&self) -> &[NodeSpec] {
        &self.nodes
    }

    pub fn connections(&self) -> &[Connection] {
        &self.connections
    }

    pub fn add_node(&mut self, node: NodeSpec) -> Result<(), GraphError> {
        if self.nodes.iter().any(|existing| existing.id == node.id) {
            return Err(GraphError::DuplicateNode(node.id));
        }
        self.nodes.push(node);
        Ok(())
    }

    pub fn connect(&mut self, connection: Connection) -> Result<(), GraphError> {
        if self.connections.contains(&connection) {
            return Err(GraphError::DuplicateConnection(connection));
        }
        self.connections.push(connection);
        if let Err(error) = self.validate() {
            self.connections.pop();
            return Err(error);
        }
        Ok(())
    }

    /// Validates node/port references, signal types, channel layouts, and cycles.
    /// This is control-thread work and must not be called from an audio callback.
    pub fn validate(&self) -> Result<(), GraphError> {
        let mut by_id = HashMap::with_capacity(self.nodes.len());
        for node in &self.nodes {
            if by_id.insert(node.id, node).is_some() {
                return Err(GraphError::DuplicateNode(node.id));
            }
        }

        let mut edges: HashMap<NodeId, Vec<NodeId>> = HashMap::new();
        for connection in &self.connections {
            let Some(from) = by_id.get(&connection.from_node) else {
                return Err(GraphError::MissingNode(connection.from_node));
            };
            let Some(to) = by_id.get(&connection.to_node) else {
                return Err(GraphError::MissingNode(connection.to_node));
            };
            let Some(output) = from.outputs.get(connection.from_port) else {
                return Err(GraphError::InvalidOutputPort {
                    node: connection.from_node,
                    port: connection.from_port,
                });
            };
            let Some(input) = to.inputs.get(connection.to_port) else {
                return Err(GraphError::InvalidInputPort {
                    node: connection.to_node,
                    port: connection.to_port,
                });
            };
            if output.kind != input.kind || output.channels != input.channels {
                return Err(GraphError::IncompatiblePorts {
                    from: connection.from_node,
                    to: connection.to_node,
                });
            }
            edges.entry(connection.from_node).or_default().push(connection.to_node);
        }

        // Kahn's algorithm detects cycles in the directed processing graph.
        let mut indegree: HashMap<NodeId, usize> =
            self.nodes.iter().map(|node| (node.id, 0)).collect();
        for targets in edges.values() {
            for target in targets {
                *indegree.entry(*target).or_default() += 1;
            }
        }
        let mut ready: Vec<NodeId> = indegree
            .iter()
            .filter_map(|(id, degree)| (*degree == 0).then_some(*id))
            .collect();
        let mut visited = 0;
        while let Some(node) = ready.pop() {
            visited += 1;
            if let Some(targets) = edges.get(&node) {
                for target in targets {
                    let degree = indegree.get_mut(target).expect("node was validated");
                    *degree -= 1;
                    if *degree == 0 {
                        ready.push(*target);
                    }
                }
            }
        }
        if visited != self.nodes.len() {
            return Err(GraphError::CycleDetected);
        }
        Ok(())
    }

    /// Returns a topological processing order when the graph is valid.
    pub fn processing_order(&self) -> Result<Vec<NodeId>, GraphError> {
        self.validate()?;
        let mut indegree: HashMap<NodeId, usize> =
            self.nodes.iter().map(|node| (node.id, 0)).collect();
        let mut edges: HashMap<NodeId, Vec<NodeId>> = HashMap::new();
        for connection in &self.connections {
            edges.entry(connection.from_node).or_default().push(connection.to_node);
            *indegree.entry(connection.to_node).or_default() += 1;
        }
        let mut ready: Vec<NodeId> = self.nodes.iter()
            .filter_map(|node| (indegree[&node.id] == 0).then_some(node.id))
            .collect();
        let mut order = Vec::with_capacity(self.nodes.len());
        while let Some(node) = ready.pop() {
            order.push(node);
            if let Some(targets) = edges.get(&node) {
                for target in targets {
                    let degree = indegree.get_mut(target).expect("node was validated");
                    *degree -= 1;
                    if *degree == 0 {
                        ready.push(*target);
                    }
                }
            }
        }
        Ok(order)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn audio_node(id: u64, input: bool, output: bool) -> NodeSpec {
        NodeSpec {
            id: NodeId(id),
            name: format!("node-{id}"),
            inputs: if input { vec![Port::new("in", SignalKind::Audio, 2)] } else { vec![] },
            outputs: if output { vec![Port::new("out", SignalKind::Audio, 2)] } else { vec![] },
        }
    }

    #[test]
    fn accepts_compatible_audio_connection_and_orders_nodes() {
        let mut graph = AudioGraph::new();
        graph.add_node(audio_node(1, false, true)).unwrap();
        graph.add_node(audio_node(2, true, false)).unwrap();
        graph.connect(Connection { from_node: NodeId(1), from_port: 0, to_node: NodeId(2), to_port: 0 }).unwrap();
        let order = graph.processing_order().unwrap();
        assert_eq!(order.len(), 2);
        assert!(order.iter().position(|id| *id == NodeId(1)).unwrap()
            < order.iter().position(|id| *id == NodeId(2)).unwrap());
    }

    #[test]
    fn rejects_incompatible_signal_kinds() {
        let mut graph = AudioGraph::new();
        graph.add_node(NodeSpec {
            id: NodeId(1), name: "control-source".into(), inputs: vec![],
            outputs: vec![Port::new("out", SignalKind::Control, 1)],
        }).unwrap();
        graph.add_node(NodeSpec {
            id: NodeId(2), name: "audio-sink".into(), inputs: vec![Port::new("in", SignalKind::Audio, 2)],
            outputs: vec![],
        }).unwrap();
        assert_eq!(
            graph.connect(Connection { from_node: NodeId(1), from_port: 0, to_node: NodeId(2), to_port: 0 }),
            Err(GraphError::IncompatiblePorts { from: NodeId(1), to: NodeId(2) })
        );
    }

    #[test]
    fn rejects_cycles() {
        let mut graph = AudioGraph::new();
        graph.add_node(audio_node(1, true, true)).unwrap();
        graph.add_node(audio_node(2, true, true)).unwrap();
        graph.connect(Connection { from_node: NodeId(1), from_port: 0, to_node: NodeId(2), to_port: 0 }).unwrap();
        assert_eq!(
            graph.connect(Connection { from_node: NodeId(2), from_port: 0, to_node: NodeId(1), to_port: 0 }),
            Err(GraphError::CycleDetected)
        );
    }
}
