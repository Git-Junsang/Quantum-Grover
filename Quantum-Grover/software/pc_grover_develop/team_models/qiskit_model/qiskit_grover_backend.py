"""Qiskit Aer reference for one independently initialized Grover attempt."""

from __future__ import annotations

from dataclasses import asdict, dataclass
from importlib.metadata import PackageNotFoundError, version
from numbers import Integral
from time import perf_counter
from typing import Any

import numpy as np


class QiskitDependencyError(RuntimeError):
    pass


@dataclass(frozen=True)
class PreparedQiskitCircuit:
    backend: Any
    circuit: Any
    target_mask: np.ndarray
    requested_j: int
    qubits: int
    build_seconds: float
    transpile_seconds: float
    high_level_depth: int
    high_level_operations: int
    transpiled_depth: int
    transpiled_operations: int


@dataclass(frozen=True)
class QiskitGroverResult:
    amplitudes: np.ndarray
    target_probability: float
    norm: float
    execution_seconds: float
    requested_j: int
    target_count: int
    qubits: int


@dataclass(frozen=True)
class QiskitComparison:
    direct_l2_error: float
    phase_aligned_l2_error: float
    maximum_amplitude_error: float
    success_probability_error: float
    reference_norm_error: float
    qiskit_norm_error: float
    maximum_imaginary_component: float

    def to_dict(self) -> dict[str, float]:
        return asdict(self)


def qiskit_available() -> bool:
    try:
        _imports()
    except QiskitDependencyError:
        return False
    return True


def package_versions() -> dict[str, str | None]:
    result: dict[str, str | None] = {}
    for package in ("qiskit", "qiskit-aer", "numpy"):
        try:
            result[package] = version(package)
        except PackageNotFoundError:
            result[package] = None
    return result


def build_requested_j_circuit(
    target_mask: np.ndarray,
    requested_j: int,
) -> Any:
    """Build H^q -> (Oracle -> Diffusion)^j -> save_statevector.

    A ``DiagonalGate`` stores only the 2^q diagonal entries, not a dense
    2^q-by-2^q matrix.  Qiskit's integer basis ordering equals the golden
    model's array index ordering.
    """

    QuantumCircuit, DiagonalGate, _, _ = _imports()
    mask = _validate_mask(target_mask)
    j = _validate_j(requested_j)
    q = mask.size.bit_length() - 1
    qubits = list(range(q))

    oracle_values = np.ones(mask.size, dtype=np.complex128)
    oracle_values[mask] = -1.0
    zero_reflection_values = np.full(mask.size, -1.0, dtype=np.complex128)
    zero_reflection_values[0] = 1.0
    oracle = DiagonalGate(oracle_values)
    zero_reflection = DiagonalGate(zero_reflection_values)

    circuit = QuantumCircuit(q, name="grover_requested_j")
    circuit.h(qubits)
    for _ in range(j):
        circuit.append(oracle, qubits)
        circuit.h(qubits)
        circuit.append(zero_reflection, qubits)
        circuit.h(qubits)
    circuit.save_statevector(label="final_statevector")
    return circuit


def prepare_requested_j(
    target_mask: np.ndarray,
    requested_j: int,
    *,
    optimization_level: int = 0,
    threads: int = 1,
) -> PreparedQiskitCircuit:
    """Build and transpile once; repeated timing measures execution only."""

    _, _, AerSimulator, transpile = _imports()
    mask = _validate_mask(target_mask)
    _validate_optimization_level(optimization_level)
    if isinstance(threads, bool) or not isinstance(threads, Integral) or threads < 1:
        raise ValueError("threads must be a positive integer")

    started = perf_counter()
    high_level = build_requested_j_circuit(mask, requested_j)
    build_seconds = perf_counter() - started
    backend = AerSimulator(
        method="statevector",
        device="CPU",
        precision="double",
        max_parallel_threads=int(threads),
    )
    started = perf_counter()
    compiled = transpile(
        high_level,
        backend,
        optimization_level=int(optimization_level),
    )
    transpile_seconds = perf_counter() - started
    return PreparedQiskitCircuit(
        backend=backend,
        circuit=compiled,
        target_mask=mask.copy(),
        requested_j=int(requested_j),
        qubits=mask.size.bit_length() - 1,
        build_seconds=build_seconds,
        transpile_seconds=transpile_seconds,
        high_level_depth=int(high_level.depth()),
        high_level_operations=int(high_level.size()),
        transpiled_depth=int(compiled.depth()),
        transpiled_operations=int(compiled.size()),
    )


def execute_prepared(
    prepared: PreparedQiskitCircuit,
) -> QiskitGroverResult:
    started = perf_counter()
    result = prepared.backend.run(prepared.circuit).result()
    execution_seconds = perf_counter() - started
    amplitudes = np.asarray(
        result.data(0)["final_statevector"], dtype=np.complex128
    ).copy()
    probabilities = np.square(np.abs(amplitudes), dtype=np.float64)
    return QiskitGroverResult(
        amplitudes=amplitudes,
        target_probability=float(
            np.sum(probabilities[prepared.target_mask], dtype=np.float64)
        ),
        norm=float(np.sum(probabilities, dtype=np.float64)),
        execution_seconds=execution_seconds,
        requested_j=prepared.requested_j,
        target_count=int(np.count_nonzero(prepared.target_mask)),
        qubits=prepared.qubits,
    )


def run_requested_j(
    target_mask: np.ndarray,
    requested_j: int,
    *,
    optimization_level: int = 0,
    threads: int = 1,
) -> tuple[PreparedQiskitCircuit, QiskitGroverResult]:
    prepared = prepare_requested_j(
        target_mask,
        requested_j,
        optimization_level=optimization_level,
        threads=threads,
    )
    return prepared, execute_prepared(prepared)


def compare_with_reference(
    reference_amplitudes: np.ndarray,
    qiskit_amplitudes: np.ndarray,
    target_mask: np.ndarray,
) -> QiskitComparison:
    reference = _validate_state(reference_amplitudes, "reference_amplitudes")
    candidate = _validate_state(qiskit_amplitudes, "qiskit_amplitudes")
    mask = _validate_mask(target_mask)
    if reference.size != candidate.size or reference.size != mask.size:
        raise ValueError("statevectors and target_mask must have equal length")

    overlap = np.vdot(reference, candidate)
    correction = (
        1.0 + 0.0j
        if abs(overlap) == 0.0
        else np.exp(-1j * np.angle(overlap))
    )
    aligned = candidate * correction
    reference_prob = np.square(np.abs(reference), dtype=np.float64)
    candidate_prob = np.square(np.abs(candidate), dtype=np.float64)
    return QiskitComparison(
        direct_l2_error=float(np.linalg.norm(candidate - reference)),
        phase_aligned_l2_error=float(np.linalg.norm(aligned - reference)),
        maximum_amplitude_error=float(np.max(np.abs(aligned - reference))),
        success_probability_error=abs(
            float(np.sum(candidate_prob[mask], dtype=np.float64))
            - float(np.sum(reference_prob[mask], dtype=np.float64))
        ),
        reference_norm_error=abs(float(np.sum(reference_prob)) - 1.0),
        qiskit_norm_error=abs(float(np.sum(candidate_prob)) - 1.0),
        maximum_imaginary_component=float(np.max(np.abs(candidate.imag))),
    )


def _imports() -> tuple[Any, Any, Any, Any]:
    try:
        from qiskit import QuantumCircuit, transpile
        from qiskit.circuit.library import DiagonalGate
        from qiskit_aer import AerSimulator
    except (ImportError, OSError) as exc:
        raise QiskitDependencyError(
            "qiskit and qiskit-aer are required; install requirements-qiskit.txt"
        ) from exc
    return QuantumCircuit, DiagonalGate, AerSimulator, transpile


def _validate_mask(target_mask: np.ndarray) -> np.ndarray:
    mask = np.asarray(target_mask)
    if mask.ndim != 1:
        raise ValueError("target_mask must be one-dimensional")
    if mask.dtype != np.bool_:
        raise TypeError("target_mask must have boolean dtype")
    if mask.size < 2 or mask.size & (mask.size - 1):
        raise ValueError("target_mask length must be a power of two")
    return mask


def _validate_state(values: np.ndarray, name: str) -> np.ndarray:
    state = np.asarray(values, dtype=np.complex128)
    if state.ndim != 1:
        raise ValueError(f"{name} must be one-dimensional")
    if state.size < 2 or state.size & (state.size - 1):
        raise ValueError(f"{name} length must be a power of two")
    if not np.all(np.isfinite(state)):
        raise ValueError(f"{name} must contain finite values")
    return state


def _validate_j(requested_j: int) -> int:
    if isinstance(requested_j, bool) or not isinstance(requested_j, Integral):
        raise TypeError("requested_j must be an integer")
    if not 0 <= requested_j <= 127:
        raise ValueError("requested_j must fit the v0.9.8 unsigned 7-bit field")
    return int(requested_j)


def _validate_optimization_level(level: int) -> None:
    if isinstance(level, bool) or not isinstance(level, Integral) or not 0 <= level <= 3:
        raise ValueError("optimization_level must be 0, 1, 2, or 3")
