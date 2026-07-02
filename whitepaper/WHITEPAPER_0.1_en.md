# World Quantum Computer (WQC) v0.1
### ~ A Decentralized Quantum Simulation Protocol to Shatter Centralized Hegemony ~

### 1. Preface: Rebellion Against Quantum Hegemony (Anti-Hegemony)

Current quantum computing is creating a "digital divide of the new era". Nations and corporations with multi-billion dollar facilities are attempting to monopolize the keys to new drugs, new materials, and cryptography. WQC invalidates this monopoly of the privileged class not by building a single giant physical computer, but by "**connecting all devices on Earth as a single nervous system**".

### 2. "Physical and Structural" Challenges to Solve
- **Censorship by Wealth**:
    Access rights to physical quantum machines are currently vetted by giant corporations based on "who" uses them and "for what". This is censorship against scientific freedom.

- **The Memory Wall**:
    Simulating over 50 Qubits requires petabytes of memory, making it cost-prohibitive to load onto a single supercomputer.

- **The Futility of PoW**:
    Existing mining wastes electricity on "meaningless hash calculations". This must be converted to "computations directly linked to human progress" (PoUW).

### 3. Technical Breakthrough: Hyper-Distributed Tensor Contraction

#### 3.1 Tensor Network Slicing (Advanced Partitioning)

Treating quantum circuits as tensor networks, we dynamically identify areas with low "**Bond Dimension**".

- **Slicing Technology**:
    Dividing the circuit into thousands of "slices". Each slice can be computed independently, allowing even standard PCs with only a few GB of RAM to share a portion of large-scale circuits.

#### 3.2 ASIC-Resistant Algorithm: Quantum-Argon2 Hybrid

- **Memory-Hard Implementation**:
    Setting the computational bottleneck to "memory bandwidth and capacity" rather than "computation speed (hashing)".

- **Anti-ASIC Strategy**:
    Tuning the algorithm so that gaming GPUs with expensive VRAM and Apple Silicon with unified memory operate most efficiently, making it physically difficult for dedicated ASIC farms to dominate the network.

#### 3.3 "Trustless" Verification via zk-STARKs

When tens of thousands of nodes perform calculations, their results are verified without re-computation.

- **Proof of Computation**:
    Worker Nodes generate a zero-knowledge proof of "computing with the correct process" simultaneously with the calculation. The Orchestrator verifies its validity in milliseconds and finalizes the reward ($WQC).

### 4. Ultimate Tokenomics: Pure Fair Launch 2.0

#### 4.1 Completely Fair Distribution Schedule

- **0% Pre-sale / VC Allocation**:
    Everyone can acquire tokens solely through "providing computational power to the network" or "contributing to the ecosystem".

- **Genesis Mining**:
    In Phase 1, a high "Early-Adopter Multiplier" is applied to users who spin up nodes early, building community-driven liquidity.

#### 4.2 The Reality of PoUW (Proof of Useful Work)

The $WQC reward is not merely inflationary issuance. The "usage fees ($WQC)" paid by corporations and research institutions when utilizing the WQC network serve as the source of rewards for Worker Nodes.

- **Burn Mechanism**:
    20% of the usage fees are permanently Burned, adopting a deflationary design where the scarcity value of $WQC increases as the number of users grows.

### 5. Roadmap: Countdown to the Singularity

- **Phase 1 (Genesis)**:
    2025. Implementation of the ASIC-resistant PoUW algorithm and stable operation of a 15-Qubit class network with the first 1,000 nodes.

- **Phase 2 (Democratization)**:
    User expansion via "contribution rewards" rather than airdrops. Automation of low-cost reward payouts via L2s such as Base/Arbitrum.

- **Phase 3 (Quantum Supremacy via Swarm)**:
    Achieving 100-Qubit class computational capability. This is the moment a decentralized network acquires computing power rivaling the world's top supercomputers.

- **Phase 4 (The Web of Light)**:
    Integrating physical quantum computers (actual machines) as nodes, evolving into a hybrid platform that unifies simulation and real-machine computation.

### 6. Conclusion: We are the Computer.

WQC is not a product of a single company. It is the "**strongest intelligence without a centralized master**" that humanity will possess for the first time. We do not own the computer; we become the computer itself.

---
### WQC Technical Appendix: Deep Dive into Distributed Quantum Simulation1.


#### 1. Mathematical Model: Tensor Network Partition Computation

Conventional simulations fail by attempting to expand the entire state vector $2^n$ in memory. WQC treats the circuit as a **Tensor Network (TN)** and performs distributed processing based on the following formula.

#### 1.1 Circuit Slicing (Bond Index Slicing)
When calculating the amplitude $A$ of a quantum circuit, fixing (Slicing) a specific Bond Index $i$ decomposes the computation into independent subtasks.

$$A = \sum_{i_1, i_2, \dots, i_k} T_{i_1} \cdot T_{i_2} \dots T_{i_n}$$

By slicing this with $k$ indices, it generates $2^k$ independent jobs.

- **Role of the Orchestrator**:
    Using graph theory, it calculates the Optimal Contraction Path that minimizes contraction costs (computational complexity), cutting the jobs into sizes that fit within the average VRAM capacity of nodes (e.g., 8GB-12GB).


#### 2. Algorithm Flow: PoUW Execution Cycle

The flow that realizes the steps until a node earns rewards in a "Trustless" environment.

1. Task Batching (Orchestrator)

    - Partitions the 100-Qubit class circuit submitted by the client into thousands of Slice Tasks.
    - Assigns a unique Task_ID and a seed value for verification to each task.

2. Commitment Phase (Worker Node)
    - The node requests a task. At this time, a small amount of $WQC is temporarily locked (Soft-Staking) to prevent fraud (Sybil Attack countermeasures).

3. Execution & Proof Generation (Worker Node)
    - Launches the Quantum-Argon2 Hybrid Engine.
    - While executing the calculation, it uses zk-STARKs (Zero-Knowledge Scalable Transparent Arguments of Knowledge) to generate a polynomial proof of the computational process.
    - _Point_: By allocating computational resources to "proof generation" rather than the "computation itself", it makes tampering with the results impossible.

4. Verification & Settlement (Aggregator/Smart Contract)
    - The Aggregator receives the proof and verifies it instantly.
    - Upon passing verification, the smart contract automatically sends $WQC to the Worker Node's wallet.
    - Simultaneously aggregates the calculation results (partial tensor values).


#### 3. Mathematical Basis for ASIC Resistance: The Memory-Bound Wall

The reason ASICs cannot monopolize the WQC network lies in the design of the algorithm's **Arithmetic Intensity**.

- Design Formula:

$$I = \frac{\text{Floating Point Operations (FLOPs)}}{\text{Memory Access (Bytes)}}$$

- WQC's Strategy: Intentionally keep the value of $I$ low.

    - ASICs have high computational performance (FLOPs), but loading them with massive amounts of high-bandwidth memory (like HBM) increases manufacturing costs exponentially.
    - On the other hand, the latest GPUs (e.g., RTX 4090) and Apple M4 Max already possess extremely high memory bandwidth.
    - This forcibly creates a state where "**it yields a higher ROI (Return on Investment) to use commercially available high-end PCs rather than building dedicated machines**".


#### 4. System Architecture Diagram (Image)

```
[ Client: Research Lab/DAO ]
          |
          v (Pay $WQC)
+----------------------------+
|    WQC ORCHESTRATOR        | <--- [ Graph-based Circuit Partitioning ]
+----------------------------+
          |
    (Distribute Slice Tasks)
          |
    +-----+-----------+-----------+-----+
    |                 |                 |
[ Node A (PC) ]   [ Node B (GPU) ]   [ Node C (Mac) ]
(zk-STARK Proof)  (zk-STARK Proof)   (zk-STARK Proof)
    |                 |                 |
    +-----+-----------+-----------+-----+
          |
    (Result Aggregation)
          |
[ Final Quantum Result ] ---> [ Distributed to Client ]
```
