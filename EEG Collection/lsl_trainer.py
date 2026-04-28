"""
lsl_trainer.py

Single script with 4 runnable modes controlled by --mode:
  1) ui_only            -> Test Pygame UI only (no LSL, no EEG, no model)
  2) eeg_only           -> Test EEG LSL I/O + timing (no model/feedback)
  3) sim_eeg_model      -> Use a virtual LSL EEG stream + markers + model/feedback
  4) full               -> Real EEG LSL + calibration + few-shot finetune + online feedback

Also supports: saving calibration windows, exporting ONNX after finetune.

Author: Yangyulin Ai (BCI MI Project)
Python >= 3.9; pip install: torch numpy scipy pylsl pygame

Configuration: Uses config.json for class definitions and parameters.
"""
from __future__ import annotations
import os, sys, time, math, json, threading, queue, signal, argparse, random
from dataclasses import dataclass, asdict
from typing import List, Tuple, Deque, Optional
from collections import deque

import numpy as np
from scipy.signal import butter, sosfiltfilt

import torch
import torch.nn as nn
import torch.nn.functional as F
from torch.utils.data import Dataset, DataLoader

# LSL / UI
try:
    from pylsl import StreamInlet, StreamInfo, StreamOutlet, resolve_byprop, local_clock
except Exception:
    StreamInlet = StreamInfo = StreamOutlet = resolve_byprop = local_clock = None  # ui_only fallback
import pygame

# Configuration loader
from config_loader import BCIConfig

# ==========================
# ====== CONFIG BLOCK ======
# ==========================
@dataclass
class LSLConfig:
    eeg_name: str = "EEG"           # LSL EEG stream name
    eeg_type: str = "EEG"
    eeg_min_srate: int = 200
    marker_name: str = "Markers"
    channel_names: Tuple[str, str, str] = ("C3", "C4", "Cz")
    # Optional zero-based indices to use when channel labels are unavailable.
    # Default (2,5,3) means: channel3->C3, channel6->Cz, channel4->C4
    channel_indices: Optional[Tuple[int, int, int]] = (2, 3, 5)

@dataclass
class TrialDesign:
    n_trials_per_class: int = 30
    classes: Tuple[int, ...] = ()  # Will be loaded from config
    trial_len: float = 8.0
    fixation_on: float = 0.0
    cue_on: float = 2.0
    mi_start: float = 2.0
    mi_stop: float = 6.0
    rest_on: float = 6.0
    
    @classmethod
    def from_config(cls, bci_config: BCIConfig, n_trials_per_class: int = None):
        """Create TrialDesign from BCIConfig"""
        trial_params = bci_config.get_trial_design_params()
        if n_trials_per_class is None:
            n_trials_per_class = trial_params.get('n_trials_per_class', 30)
        
        return cls(
            n_trials_per_class=n_trials_per_class,
            classes=bci_config.class_codes,
            trial_len=trial_params.get('trial_len', 8.0),
            fixation_on=trial_params.get('fixation_on', 0.0),
            cue_on=trial_params.get('cue_on', 2.0),
            mi_start=trial_params.get('mi_start', 2.0),
            mi_stop=trial_params.get('mi_stop', 6.0),
            rest_on=trial_params.get('rest_on', 6.0),
        )

@dataclass
class PreprocConfig:
    sfreq_target: int = 250
    f_lo: float = 4.0
    f_hi: float = 38.0
    iir_order: int = 4
    exp_alpha: float = 0.001  # exponential moving standardization
    exp_init: int = 1000

@dataclass
class WindowConfig:
    win_start: float = 0.5
    win_stop: float = 3.0

@dataclass
class TrainConfig:
    device: str = "cuda" if torch.cuda.is_available() else "cpu"
    batch_size: int = 64
    epochs: int = 5
    lr: float = 1e-4
    weight_decay: float = 1e-4
    freeze_features: bool = True
    num_workers: int = 0
    early_stop_patience: int = 3

@dataclass
class Paths:
    session_dir: str = "./session_stage2"
    calib_npz: str = "./session_stage2/calib_windows.npz"
    finetuned_pt: str = "./session_stage2/finetuned.pt"
    finetuned_onnx: str = "./session_stage2/finetuned.onnx"
    PRETRAINED_CKPT: Optional[str] = None  # e.g., "./ckpts/stage1_best.pt"

# Event codes (standard LSL marker codes)
# Note: Actual MI class codes are loaded from config.json
EV_RUN_START = 32766
EV_TRIAL_START = 768
EV_CONT_FEEDBACK = 781
EV_MI_END = 782
EV_TRIAL_BAD = 1023

# Legacy event codes for reference (now loaded from config)
EV_MI_LEFT = 769
EV_MI_RIGHT = 770
EV_MI_UP = 771
EV_MI_DOWN = 772

# ===============================
# ====== UTILS & PREPROCESS ======
# ===============================
def set_seed(seed: int = 42):
    random.seed(seed)
    np.random.seed(seed)
    torch.manual_seed(seed)
    torch.cuda.manual_seed_all(seed)
    torch.backends.cudnn.deterministic = True
    torch.backends.cudnn.benchmark = False

class Bandpass:
    def __init__(self, sfreq: int, f_lo: float, f_hi: float, order: int = 4):
        nyq = 0.5 * sfreq
        Wn = [f_lo / nyq, f_hi / nyq]
        self.sos = butter(order, Wn, btype='band', output='sos')
    def __call__(self, x: np.ndarray) -> np.ndarray:
        return sosfiltfilt(self.sos, x, axis=1)

class ExpMovStandardizer:
    def __init__(self, alpha: float = 0.001, init_samples: int = 1000):
        self.alpha = alpha
        self.init_samples = init_samples
        self.mean = None
        self.var = None
        self.init_count = 0
    def reset(self):
        self.mean, self.var, self.init_count = None, None, 0
    def fit_chunk(self, x: np.ndarray):
        if self.mean is None:
            self.mean = x[:, :1].copy(); self.var = np.ones_like(self.mean); self.init_count = 0
        for t in range(x.shape[1]):
            xt = x[:, t:t+1]
            if self.init_count < self.init_samples:
                self.mean = (self.mean * self.init_count + xt) / (self.init_count + 1)
                self.var = (self.var * self.init_count + (xt - self.mean) ** 2) / (self.init_count + 1)
                self.init_count += 1
            else:
                self.mean = (1 - self.alpha) * self.mean + self.alpha * xt
                self.var  = (1 - self.alpha) * self.var  + self.alpha * (xt - self.mean) ** 2
        return self
    def transform(self, x: np.ndarray) -> np.ndarray:
        if self.mean is None:
            self.fit_chunk(x)
        std = np.sqrt(self.var + 1e-8)
        return (x - self.mean) / std

# =======================
# ====== EEG MODEL  =====
# =======================
class EEGNetSmall(nn.Module):
    """A compact EEGNet-ish classifier for 3 channels.
    Input: (B, 1, C=3, T) -> logits (B, n_classes)
    """
    def __init__(self, n_ch=3, n_classes=4, samples=800):
        super().__init__()
        self.n_classes = n_classes
        self.conv_time = nn.Conv2d(1, 8, (1, 64), padding=(0, 32), bias=False)
        self.bn1 = nn.BatchNorm2d(8)
        self.conv_depth = nn.Conv2d(8, 16, (n_ch, 1), groups=8, bias=False)
        self.bn2 = nn.BatchNorm2d(16)
        self.conv_sep = nn.Conv2d(16, 16, (1, 16), padding=(0, 8), bias=False)
        self.bn3 = nn.BatchNorm2d(16)
        self.pool1 = nn.AvgPool2d((1, 8))
        self.drop = nn.Dropout(0.5)
        with torch.no_grad():
            dummy = torch.zeros(1, 1, n_ch, samples)
            y = self.forward_features(dummy)
            flat = y.shape[1]
        self.fc = nn.Linear(flat, n_classes)
    def forward_features(self, x):
        x = F.elu(self.bn1(self.conv_time(x)))
        x = F.elu(self.bn2(self.conv_depth(x)))
        x = F.elu(self.bn3(self.conv_sep(x)))
        x = self.pool1(x)
        x = self.drop(x)
        x = torch.flatten(x, 1)
        return x
    def forward(self, x):
        return self.fc(self.forward_features(x))

# ==================================
# ====== LSL IO & RING BUFFER  =====
# ==================================
class EEGInlet:
    def __init__(self, cfg: LSLConfig, timeout=10.0):
        if resolve_byprop is None:
            raise RuntimeError("pylsl not available (UI-only mode or missing dependency)")
        print("Resolving EEG stream...")
        streams = resolve_byprop('type', cfg.eeg_type, timeout=timeout)
        if len(streams) == 0:
            raise RuntimeError("No EEG stream found via LSL")
        chosen = None
        if cfg.eeg_name:
            for si in streams:
                if si.name() == cfg.eeg_name:
                    chosen = si; break
        if chosen is None:
            chosen = streams[0]
        print(f"Using EEG stream: {chosen.name()} @ {chosen.nominal_srate()} Hz, {chosen.channel_count()} ch")
        # Print channel labels if available
        try:
            labels = []
            desc = chosen.desc().child("channels").child("channel")
            while desc and desc.name():
                lab = desc.child_value("label")
                labels.append(lab if lab else "<unnamed>")
                desc = desc.next_sibling()
            if labels:
                print(f"Channel labels: {labels}")
        except Exception as ex:
            print(f"Warning: unable to read channel labels ({ex})")
        if chosen.nominal_srate() < cfg.eeg_min_srate:
            print("Warning: low sampling rate; proceeding anyway")
        self.inlet = StreamInlet(chosen, max_buflen=60)
        self.info = chosen
    def pull_chunk(self, timeout=0.0):
        return self.inlet.pull_chunk(timeout=timeout)

class MarkerOutlet:
    def __init__(self, name: str = "Markers", on_push=None):
        if StreamInfo is None:
            self.outlet = None
            print("Marker outlet disabled (no pylsl)")
            return
        info = StreamInfo(name, 'Markers', 1, 0, 'int32', 'mi_markers')
        self.outlet = StreamOutlet(info)
        self.on_push = on_push
        print(f"Marker outlet created: {name}")
    def push(self, code: int):
        if self.outlet is not None:
            self.outlet.push_sample([int(code)])
        if self.on_push:
            try:
                clk = local_clock() if 'local_clock' in globals() and local_clock else time.time()
                self.on_push(int(code), clk)
            except Exception:
                pass

class RingBuffer:
    def __init__(self, n_ch: int, capacity_s: float, sfreq: int):
        self.n_ch = n_ch; self.sf = sfreq
        self.cap = int(capacity_s * sfreq)
        self.buf = np.zeros((n_ch, self.cap), dtype=np.float32)
        self.idx = 0; self.filled = False; self.lock = threading.Lock()
        self.total_written = 0  # absolute sample counter
    def append(self, x: np.ndarray):
        with self.lock:
            T = x.shape[1]
            if T >= self.cap:
                self.buf = x[:, -self.cap:]; self.idx = 0; self.filled = True; return
            end = self.idx + T
            if end <= self.cap:
                self.buf[:, self.idx:end] = x
            else:
                part1 = self.cap - self.idx
                self.buf[:, self.idx:] = x[:, :part1]
                self.buf[:, :T-part1] = x[:, part1:]
                self.filled = True
            self.idx = (self.idx + T) % self.cap
            self.total_written += T
    def get_last(self, n_samples: int) -> np.ndarray:
        with self.lock:
            if not self.filled and self.idx < n_samples:
                raise ValueError("Not enough data yet")
            start = (self.idx - n_samples) % self.cap
            if start + n_samples <= self.cap:
                return self.buf[:, start:start+n_samples].copy()
            else:
                part1 = self.cap - start
                return np.hstack((self.buf[:, start:], self.buf[:, :n_samples-part1])).copy()
    def get_by_end_counter(self, end_counter: int, n_samples: int) -> np.ndarray:
        """Return n_samples ending at absolute end_counter (exclusive)."""
        with self.lock:
            if not self.filled and self.total_written < n_samples:
                raise ValueError("Not enough data yet")
            end_idx = end_counter % self.cap
            start = (end_idx - n_samples) % self.cap
            if start + n_samples <= self.cap:
                return self.buf[:, start:start+n_samples].copy()
            else:
                part1 = self.cap - start
                return np.hstack((self.buf[:, start:], self.buf[:, :n_samples-part1])).copy()

# =====================================
# ====== PREPROC PIPELINE (ONLINE) =====
# =====================================
class OnlinePreproc:
    def __init__(self, pp: PreprocConfig, enforce_order: Tuple[str, str, str],
                 enforce_indices: Optional[Tuple[int, int, int]] = None):
        self.pp = pp; self.enforce_order = enforce_order
        self.enforce_indices = enforce_indices
        self.bandpass = Bandpass(pp.sfreq_target, pp.f_lo, pp.f_hi, pp.iir_order)
        self.ems = ExpMovStandardizer(pp.exp_alpha, pp.exp_init)
    def resample_if_needed(self, x: np.ndarray, sf_in: float) -> np.ndarray:
        if abs(sf_in - self.pp.sfreq_target) < 1e-3:
            return x
        C, T = x.shape; dur = T / sf_in
        t_old = np.linspace(0, dur, T, endpoint=False)
        T_new = int(round(dur * self.pp.sfreq_target))
        t_new = np.linspace(0, dur, T_new, endpoint=False)
        y = np.vstack([np.interp(t_new, t_old, x[c]) for c in range(C)])
        return y
    def enforce_channels(self, names: List[str], data: np.ndarray) -> np.ndarray:
        mapping = []
        name2idx = {n:i for i,n in enumerate(names)}
        for want in self.enforce_order:
            if want in name2idx:
                mapping.append(name2idx[want])
            else:
                mapping = []
                break
        if not mapping:
            if self.enforce_indices:
                idx = []
                for i in self.enforce_indices:
                    if i < data.shape[0]:
                        idx.append(i)
                if len(idx) == 3:
                    mapping = idx
            if not mapping:
                # fallback: use first 3 channels
                mapping = list(range(min(3, data.shape[0])))
        return data[mapping]
    def __call__(self, data: np.ndarray, sf_in: float, names: List[str]) -> np.ndarray:
        x = self.enforce_channels(names, data)
        x = self.resample_if_needed(x, sf_in)
        x = self.bandpass(x)
        self.ems.fit_chunk(x)
        return self.ems.transform(x)

# =========================
# ====== DATA WINDOWS  =====
# =========================
class WindowMaker:
    def __init__(self, wc: WindowConfig, sf: int):
        self.wc = wc; self.sf = sf
    def samples(self) -> int:
        return int(round((self.wc.win_stop - self.wc.win_start) * self.sf))
    def ab(self) -> tuple[int,int]:
        a = int(round(self.wc.win_start * self.sf))
        b = int(round(self.wc.win_stop * self.sf))
        return a, b

class WinDS(Dataset):
    def __init__(self, X: np.ndarray, y: np.ndarray):
        self.X = X; self.y = y.astype(np.int64)
    def __len__(self): return self.X.shape[0]
    def __getitem__(self, i):
        x = torch.from_numpy(self.X[i]).float().unsqueeze(0)
        y = torch.tensor(self.y[i])
        return x, y

# ==========================
# ====== TRAIN / EVAL  =====
# ==========================
class Finetuner:
    def __init__(self, model: nn.Module, tc: TrainConfig):
        self.model = model.to(tc.device)
        self.tc = tc
        self.crit = nn.CrossEntropyLoss()
        self.opt = torch.optim.AdamW(filter(lambda p: p.requires_grad, self.model.parameters()), lr=tc.lr, weight_decay=tc.weight_decay)
    def train_epochs(self, dl: DataLoader, dv: Optional[DataLoader] = None):
        best = {"acc": float("-inf"), "state": None}
        patience = max(0, self.tc.early_stop_patience)
        no_improve = 0
        for ep in range(self.tc.epochs):
            self.model.train(); loss_sum = 0.0; n = 0
            for xb, yb in dl:
                xb = xb.to(self.tc.device); yb = yb.to(self.tc.device)
                self.opt.zero_grad(); logits = self.model(xb)
                loss = self.crit(logits, yb); loss.backward(); self.opt.step()
                loss_sum += loss.item() * xb.size(0); n += xb.size(0)
            train_loss = loss_sum / max(1,n)
            val_acc = self.eval_acc(dv) if dv is not None else float('nan')
            print(f"[Finetune] epoch {ep+1}/{self.tc.epochs}  train_loss={train_loss:.4f}  val_acc={val_acc:.3f}")
            if dv is not None and not math.isnan(val_acc):
                if val_acc > best["acc"]:
                    best["acc"], best["state"] = val_acc, {k:v.cpu() for k,v in self.model.state_dict().items()}
                    no_improve = 0
                else:
                    no_improve += 1
                    if patience and no_improve >= patience:
                        print(f"[Finetune] Early stopping triggered (patience={patience})")
                        break
        if best["state"] is not None:
            self.model.load_state_dict(best["state"])
    @torch.no_grad()
    def eval_acc(self, dl: DataLoader) -> float:
        if dl is None: return float('nan')
        self.model.eval(); ok = n = 0
        for xb, yb in dl:
            xb = xb.to(self.tc.device); yb = yb.to(self.tc.device)
            pred = self.model(xb).argmax(1)
            ok += (pred == yb).sum().item(); n += yb.numel()
        return ok / max(1,n)

# ==========================
# ====== PYGAME STIM  ======
# ==========================
class StimUI:
    def __init__(self, design: TrialDesign, marker: MarkerOutlet, bci_config: BCIConfig, w=800, h=400, use_feedback=True):
        self.design = design
        self.marker = marker
        self.bci_config = bci_config
        self.use_feedback = use_feedback
        pygame.init()
        self.screen = pygame.display.set_mode((w,h))
        pygame.display.set_caption("MI Stage-2")
        # font with fallback
        try:
            self.font = pygame.font.SysFont("Segoe UI Symbol", 48)
        except Exception:
            self.font = pygame.font.SysFont(None, 48)
        self.clock = pygame.time.Clock()
        self.fix_font = pygame.font.SysFont(None, 120)
        self.center = (w//2, h//2)
        self.w, self.h = w, h
    
    def draw_fixation(self, show_start_hint=False):
        self.screen.fill((0,0,0))
        txt = self.fix_font.render("+", True, (200,200,200))
        self.screen.blit(txt, txt.get_rect(center=self.center))
        if show_start_hint:
            hint = self.font.render("Press SPACE to start", True, (180,180,180))
            rect = hint.get_rect(center=(self.center[0], self.center[1] + 80))
            self.screen.blit(hint, rect)
    
    def draw_cue(self, code):
        self.screen.fill((0,0,0))
        # Get cue text from config
        cue = self.bci_config.get_cue_text(code)
        txt = self.font.render(cue, True, (0,180,255))
        self.screen.blit(txt, txt.get_rect(center=self.center))
    def draw_feedback(self, probs: Tuple[float, ...]):
        """Draw N-class feedback as circles in a pattern based on number of classes.
        probs: tuple of probabilities for each class
        """
        n_classes = len(probs)
        cx, cy = self.center
        self.screen.fill((0,0,0))
        
        max_radius = 50
        
        if n_classes == 2:
            # Binary: left-right horizontal
            positions = [(cx-150, cy), (cx+150, cy)]
        elif n_classes == 3:
            # Triangle pattern
            positions = [(cx-120, cy+60), (cx+120, cy+60), (cx, cy-80)]
        elif n_classes == 4:
            # Cross pattern (left, right, up, down)
            positions = [(cx-150, cy), (cx+150, cy), (cx, cy-150), (cx, cy+150)]
        else:
            # Circle pattern for 5+ classes
            angle_step = 2 * math.pi / n_classes
            radius = 150
            positions = []
            for i in range(n_classes):
                angle = i * angle_step - math.pi/2  # Start from top
                x = cx + int(radius * math.cos(angle))
                y = cy + int(radius * math.sin(angle))
                positions.append((x, y))
        
        # Draw connecting lines for visual structure
        if n_classes == 4:
            pygame.draw.line(self.screen, (60,60,60), (cx-150, cy), (cx+150, cy), 2)
            pygame.draw.line(self.screen, (60,60,60), (cx, cy-150), (cx, cy+150), 2)
        
        # Draw probability circles
        for i, (prob, pos) in enumerate(zip(probs, positions)):
            r = int(max_radius * prob)
            if r > 5:
                pygame.draw.circle(self.screen, (255,200,0), pos, r)
    def pump(self):
        for event in pygame.event.get():
            if event.type == pygame.QUIT:
                pygame.quit(); sys.exit(0)
    def run_calibration(self) -> List[Tuple[int, float]]:
        timeline = []
        order = list(self.design.classes) * self.design.n_trials_per_class
        random.shuffle(order)
        # Wait here until SPACE is pressed
        while True:
            start = False
            for event in pygame.event.get():
                if event.type == pygame.QUIT:
                    pygame.quit(); sys.exit(0)
                if event.type == pygame.KEYDOWN and event.key == pygame.K_SPACE:
                    start = True
            self.draw_fixation(show_start_hint=True); pygame.display.flip(); self.clock.tick(60)
            if start: break
        self.marker.push(EV_RUN_START)
        for cue_code in order:
            t0 = time.time()
            self.marker.push(EV_TRIAL_START)
            while time.time() - t0 < (self.design.cue_on - self.design.fixation_on):
                self.pump(); self.draw_fixation(); pygame.display.flip(); self.clock.tick(60)
            self.marker.push(cue_code)
            cue_t = local_clock() if 'local_clock' in globals() and local_clock else time.time()
            while time.time() - t0 < (self.design.mi_stop - self.design.fixation_on):
                self.pump(); self.draw_cue(cue_code); pygame.display.flip(); self.clock.tick(60)
            # signal MI end for SIM side reset
            self.marker.push(EV_MI_END)
            while time.time() - t0 < self.design.trial_len:
                self.pump(); self.screen.fill((0,0,0)); pygame.display.flip(); self.clock.tick(60)
            timeline.append((cue_code, cue_t))
        return timeline
    def run_online_feedback(self, prob_fn, n_trials_each=20):
        """prob_fn should return a tuple of probabilities matching number of classes"""
        order = list(self.design.classes) * n_trials_each
        random.shuffle(order)
        # Wait here until SPACE is pressed
        while True:
            start = False
            for event in pygame.event.get():
                if event.type == pygame.QUIT:
                    pygame.quit(); sys.exit(0)
                if event.type == pygame.KEYDOWN and event.key == pygame.K_SPACE:
                    start = True
            self.draw_fixation(show_start_hint=True); pygame.display.flip(); self.clock.tick(60)
            if start: break
        self.marker.push(EV_RUN_START)
        for cue_code in order:
            t0 = time.time(); self.marker.push(EV_TRIAL_START)
            while time.time() - t0 < (self.design.cue_on - self.design.fixation_on):
                self.pump(); self.draw_fixation(); pygame.display.flip(); self.clock.tick(60)
            self.marker.push(cue_code); self.marker.push(EV_CONT_FEEDBACK)
            while time.time() - t0 < (self.design.mi_stop - self.design.fixation_on):
                probs = prob_fn()
                self.pump(); self.draw_feedback(probs); pygame.display.flip(); self.clock.tick(60)
            # signal MI end for SIM side reset
            self.marker.push(EV_MI_END)
            while time.time() - t0 < self.design.trial_len:
                self.pump(); self.screen.fill((0,0,0)); pygame.display.flip(); self.clock.tick(60)

# ========================================
# ====== ACQUISITION & CALIBRATION  ======
# ========================================
class AcqThread(threading.Thread):
    def __init__(self, inlet: EEGInlet, ring_raw: RingBuffer, ch_names: List[str]):
        super().__init__(daemon=True)
        self.inlet = inlet; self.ring = ring_raw; self.ch_names = ch_names; self.running = True
    def run(self):
        print("Acquisition thread started")
        while self.running:
            data, ts = self.inlet.pull_chunk(timeout=0.1)
            if data:
                X = np.asarray(data).T
                if X.ndim == 1: X = X[:,None]
                C = min(self.ring.n_ch, X.shape[0])
                self.ring.append(X[:C, :].astype(np.float32))
    def stop(self): self.running = False

# ==================================
# ====== VIRTUAL EEG OUTLET  =======
# ==================================
class VirtualEEGOutlet(threading.Thread):
    """Simulate a 3-ch 250 Hz EEG stream with MI-like rhythms + marker outputs."""
    def __init__(self, marker: MarkerOutlet, name="EEG", sf=250, noise=5.0, get_side=None):
        super().__init__(daemon=True)
        self.sf = sf; self.noise = noise; self.running = True; self.marker = marker
        self.get_side = get_side  # callable returning 'L','R','U','D', or None
        if StreamInfo is None:
            raise RuntimeError("pylsl required for virtual EEG mode")
        info = StreamInfo(name, 'EEG', 3, sf, 'float32', 'virt_eeg')
        self.out = StreamOutlet(info)
        self.t = 0.0
    def run(self):
        print("Virtual EEG outlet started")
        chunk = int(self.sf / 10)  # 100 ms
        while self.running:
            t = (np.arange(chunk) + self.t) / self.sf
            # base alpha (10 Hz) with lateralization/direction modulation
            # simple oscillations + pink-ish noise
            left = np.sin(2*np.pi*10*t) * 10
            right = np.sin(2*np.pi*12*t + 0.5) * 10
            cz = np.sin(2*np.pi*11*t + 0.3) * 6
            # simple cue-locked modulation during MI: ERD lateralization
            side = None
            try:
                side = self.get_side() if self.get_side else None
            except Exception:
                side = None
            if side == 'L':
                left = left * 0.6
                right = right * 1.2
            elif side == 'R':
                right = right * 0.6
                left = left * 1.2
            elif side == 'U':
                # Up: attenuate both, boost Cz
                left = left * 0.7
                right = right * 0.7
                cz = cz * 1.3
            elif side == 'D':
                # Down: boost both, attenuate Cz
                left = left * 1.2
                right = right * 1.2
                cz = cz * 0.6
            noise = np.random.randn(3, chunk) * self.noise
            block = np.vstack([left, cz, right]).astype(np.float32) + noise.astype(np.float32)
            self.out.push_chunk(block.T.tolist())
            self.t += chunk
            time.sleep(0.1)
    def stop(self): self.running = False

# ==============================
# ====== MAIN ORCHESTRATOR =====
# ==============================
class Stage2Engine:
    def __init__(self, lsl: LSLConfig, td: TrialDesign, pp: PreprocConfig, wc: WindowConfig, tr: TrainConfig, paths: Paths, bci_config: BCIConfig):
        self.lsl = lsl
        self.td = td
        self.pp = pp
        self.wc = wc
        self.tr = tr
        self.paths = paths
        self.bci_config = bci_config
        os.makedirs(paths.session_dir, exist_ok=True)
        set_seed(42)
        self._running = True
        # sim_state and marker callback (for SIM mode cue-lock)
        self._sim_lock = threading.Lock()
        self._sim_side = None  # Side indicator during MI
        def _on_marker(code: int, ts: float):
            # Track side between cue_on and mi_stop (UI pushes cue then EV_CONT_FEEDBACK)
            cls = self.bci_config.get_class_by_code(code)
            if cls:
                # Map class name to side indicator
                side_map = {'left': 'L', 'right': 'R', 'up': 'U', 'down': 'D', 
                           'both_hands': 'B', 'feet': 'F', 'tongue': 'T'}
                with self._sim_lock:
                    self._sim_side = side_map.get(cls.name, None)
            elif code == EV_TRIAL_START:
                with self._sim_lock: self._sim_side = None
            elif code == EV_MI_END:
                with self._sim_lock: self._sim_side = None
        self.marker = MarkerOutlet(lsl.marker_name, on_push=_on_marker)
        # Only instantiate LSL inlet in modes that need it
        self.inlet = None; self.sf_in = None; self.ch_names = []
        self.ring_raw = None; self.ring_pre = None
        self.preproc = None; self.preproc_thread = None
        self.win_maker = WindowMaker(self.wc, self.pp.sfreq_target)
        # Model skeleton (constructed when needed)
        self.model = None
        # timeline of (clock_ts, total_written_preproc)
        self.pre_timeline = deque(maxlen=4096)
    def _get_sim_side(self):
        with self._sim_lock:
            return self._sim_side

    # ----- LSL/Preproc bring-up -----
    def start_eeg_pipeline(self):
        self.inlet = EEGInlet(self.lsl)
        self.sf_in = self.inlet.info.nominal_srate()
        n_raw = self.inlet.info.channel_count()
        # Try parse channel labels from LSL StreamInfo desc XML
        labels = []
        try:
            desc = self.inlet.info.desc()
            chs = desc.child("channels")
            ch = chs.child("channel")
            while ch.name():
                lab = ch.child_value("label")
                if lab: labels.append(lab)
                ch = ch.next_sibling()
        except Exception:
            labels = []
        if labels:
            self.ch_names = labels
        else:
            self.ch_names = [f"Ch{i+1}" for i in range(n_raw)]
        self.ring_raw = RingBuffer(n_ch=n_raw, capacity_s=60, sfreq=int(self.sf_in))
        self.ring_pre = RingBuffer(n_ch=3, capacity_s=60, sfreq=self.pp.sfreq_target)
        self.preproc = OnlinePreproc(self.pp, self.lsl.channel_names, self.lsl.channel_indices)
        self.acq = AcqThread(self.inlet, self.ring_raw, self.ch_names); self.acq.start()
        self.preproc_thread = threading.Thread(target=self._preproc_loop, daemon=True); self.preproc_thread.start()
        print("EEG pipeline started")
    def inspect_channels(self, seconds: float = 2.0):
        if self.ring_raw is None or self.sf_in is None:
            return
        needed = int(max(1, round(self.sf_in * seconds)))
        print(f"[Inspect] Capturing last {seconds:.1f}s (~{needed} samples) from raw EEG...")
        raw = None
        for _ in range(100):
            try:
                raw = self.ring_raw.get_last(needed)
                break
            except Exception:
                time.sleep(0.05)
        if raw is None:
            print("[Inspect] Unable to capture raw samples (no data yet).")
            return
        for idx in range(raw.shape[0]):
            ch = raw[idx]
            print(f"[Inspect] Ch{idx+1:02d}: mean={ch.mean():.3f}, std={ch.std():.3f}, min={ch.min():.3f}, max={ch.max():.3f}")
        if self.lsl.channel_indices:
            idxs = self.lsl.channel_indices
            labels = ("C3","Cz","C4")
            human = [i+1 for i in idxs]
            print(f"[Inspect] Using fallback indices (1-based) for {labels}: {human}")
            for lab, i in zip(labels, idxs):
                if i < raw.shape[0]:
                    ch = raw[i]
                    print(f"    {lab} (Ch{i+1:02d}): mean={ch.mean():.3f}, std={ch.std():.3f}")
                else:
                    print(f"    {lab}: index {i} out of range (only {raw.shape[0]} channels)")
    def _preproc_loop(self):
        print("Preproc thread started")
        while self._running:
            try:
                raw = self.ring_raw.get_last(int(self.sf_in * 1.0))
                x = self.preproc(raw, self.sf_in, self.ch_names)
                self.ring_pre.append(x)
                # record mapping from wall-clock to absolute sample counter
                clk = local_clock() if 'local_clock' in globals() and local_clock else time.time()
                self.pre_timeline.append((clk, self.ring_pre.total_written))
                time.sleep(0.05)
            except Exception:
                time.sleep(0.05)
                continue
    def shutdown(self):
        # stop threads and inlet
        try:
            self._running = False
        except Exception:
            pass
        try:
            if hasattr(self, 'acq') and self.acq:
                self.acq.stop()
        except Exception:
            pass
        try:
            if hasattr(self, 'preproc_thread') and self.preproc_thread:
                self.preproc_thread.join(timeout=2.0)
        except Exception:
            pass

    # ----- Calibration collection -----
    def collect_calibration(self, timeline: List[Tuple[int,float]]):
        Xs, ys = [], []
        a, b = self.win_maker.ab()
        need = b
        for cue_code, cue_ts in timeline:
            # wait until we have data up to cue_ts + win_stop
            t_end = cue_ts + self.wc.win_stop
            end_counter = None
            while True:
                snap = list(self.pre_timeline)
                if len(snap) == 0:
                    time.sleep(0.01); continue
                ts_last, ctr_last = snap[-1]
                if ts_last < t_end:
                    time.sleep(0.01); continue
                # find first entry >= t_end
                chosen_ts, chosen_ctr = None, None
                for ts_i, ctr_i in snap:
                    if ts_i >= t_end:
                        chosen_ts, chosen_ctr = ts_i, ctr_i
                        break
                if chosen_ts is None:
                    time.sleep(0.005); continue
                # adjust end_counter by sub-chunk time difference
                delta_s = chosen_ts - t_end
                adjust = int(round(delta_s * self.pp.sfreq_target))
                end_counter = chosen_ctr - adjust
                break
            # slice the last b samples ending at end_counter, then cut [a:b]
            x_b = self.ring_pre.get_by_end_counter(end_counter, b)
            x = x_b[:, a:b]
            if x.shape[1] != self.win_maker.samples(): continue
            # Map event code to class label using config
            label = self.bci_config.code_to_label_idx(cue_code)
            if label < 0:
                continue  # Unknown code, skip
            Xs.append(x.astype(np.float32))
            ys.append(label)
        X = np.stack(Xs, axis=0); y = np.asarray(ys)
        np.savez(self.paths.calib_npz, X=X, y=y)
        print(f"Saved calibration windows: {X.shape} -> {self.paths.calib_npz}")
        return X, y

    # ----- Finetune & Export -----
    def build_model(self):
        samples = self.win_maker.samples()
        n_classes = self.bci_config.n_classes
        self.model = EEGNetSmall(n_ch=3, n_classes=n_classes, samples=samples).to(self.tr.device)
        if self.paths.PRETRAINED_CKPT and os.path.isfile(self.paths.PRETRAINED_CKPT):
            print(f"Loading pretrained: {self.paths.PRETRAINED_CKPT}")
            state = torch.load(self.paths.PRETRAINED_CKPT, map_location="cpu")
            self.model.load_state_dict(state, strict=False)
        if self.tr.freeze_features:
            for n,p in self.model.named_parameters():
                if not n.startswith('fc.'):
                    p.requires_grad = False
            print("Frozen feature extractor; training classifier head only.")
    def finetune(self, X: np.ndarray, y: np.ndarray):
        # stratified split per class (supports arbitrary number of classes)
        n_classes = self.bci_config.n_classes
        cls_indices = [np.where(y == c)[0] for c in range(n_classes)]
        iv_all, it_all = [], []
        for cls_idx in cls_indices:
            if len(cls_idx) == 0:
                continue
            np.random.shuffle(cls_idx)
            n_val = max(1, int(round(0.2 * len(cls_idx))))
            iv_all.append(cls_idx[:n_val])
            it_all.append(cls_idx[n_val:])
        iv = np.concatenate(iv_all) if len(iv_all) > 0 else np.array([], dtype=int)
        it = np.concatenate(it_all) if len(it_all) > 0 else np.array([], dtype=int)
        np.random.shuffle(iv); np.random.shuffle(it)
        Xt, yt, Xv, yv = X[it], y[it], X[iv], y[iv]
        dl_t = DataLoader(WinDS(Xt, yt), batch_size=self.tr.batch_size, shuffle=True, num_workers=self.tr.num_workers)
        dl_v = DataLoader(WinDS(Xv, yv), batch_size=128, shuffle=False, num_workers=self.tr.num_workers)
        ft = Finetuner(self.model, self.tr); ft.train_epochs(dl_t, dl_v)
        torch.save(self.model.state_dict(), self.paths.finetuned_pt)
        print(f"Saved finetuned weights -> {self.paths.finetuned_pt}")
    def export_onnx(self):
        self.model.eval(); samples = self.win_maker.samples()
        dummy = torch.zeros(1,1,3,samples).to(self.tr.device)
        try:
            torch.onnx.export(self.model, dummy, self.paths.finetuned_onnx,
                              export_params=True, opset_version=18, do_constant_folding=True,
                              input_names=['eeg'], output_names=['logits'],
                              # torch>=2.1 uses torch.export under the hood; dynamic_shapes keys must match arg name(s)
                              # Our model forward(x) -> use 'x' here; only inputs are supported in dynamic_shapes
                              dynamic_shapes={'x': {0: 'B'}})
        except TypeError:
            torch.onnx.export(self.model, dummy, self.paths.finetuned_onnx,
                              export_params=True, opset_version=18, do_constant_folding=True,
                              input_names=['eeg'], output_names=['logits'],
                              dynamic_axes={'eeg': {0:'B'}, 'logits': {0:'B'}})
        print(f"Exported ONNX -> {self.paths.finetuned_onnx}")

    # ----- Inference helper -----
    @torch.no_grad()
    def online_probs(self) -> Tuple[float, ...]:
        """Return probabilities for all classes as tuple."""
        n_classes = self.bci_config.n_classes
        try:
            x = self.ring_pre.get_last(self.win_maker.samples())
        except Exception:
            uniform = 1.0 / n_classes
            return tuple([uniform] * n_classes)
        if x.shape[1] != self.win_maker.samples():
            uniform = 1.0 / n_classes
            return tuple([uniform] * n_classes)
        xb = torch.from_numpy(x).float().unsqueeze(0).unsqueeze(0).to(self.tr.device)
        probs = torch.softmax(self.model(xb), dim=1)[0]
        return tuple(float(probs[i]) for i in range(n_classes))

# ==========================
# ========== MAIN ==========
# ==========================

def parse_args():
    p = argparse.ArgumentParser(description="Stage-2 MI with multiple modes")
    p.add_argument('--mode', type=str, default='full', choices=['ui_only','eeg_only','sim_eeg_model','full'])
    p.add_argument('--config', type=str, default='config.json', help='Path to config file (default: config.json)')
    p.add_argument('--pretrained', type=str, default=None, help='Path to Stage-1 .pt')
    p.add_argument('--ncalib', type=int, default=None, help='trials per class (overrides config)')
    p.add_argument('--export_onnx', action='store_true', help='Export ONNX after finetune (full/sim)')
    p.add_argument('--subject', type=str, default=None, help='Subject ID (e.g., subj01). If provided, saves to data/{subject}/session_YYYY-MM-DD_HH-MM/')
    p.add_argument('--epochs', type=int, default=None, help='Number of finetune epochs (overrides config)')
    p.add_argument('--patience', type=int, default=None, help='Early stopping patience in epochs (overrides config)')
    return p.parse_args()

def main():
    args = parse_args()
    
    # Load configuration
    print(f"Loading configuration from {args.config}...")
    bci_config = BCIConfig(args.config)
    print(f"Loaded {bci_config.n_classes} classes: {', '.join(bci_config.class_names)}")

    lsl = LSLConfig(eeg_name="EEG", eeg_type="EEG", eeg_min_srate=200, marker_name="Markers", channel_names=("C3","Cz","C4"), channel_indices=None)
    td = TrialDesign.from_config(bci_config, n_trials_per_class=args.ncalib)
    
    # Load preprocessing and training params from config
    pp_params = bci_config.get_preprocessing_params()
    pp = PreprocConfig(
        sfreq_target=pp_params.get('sfreq_target', 250),
        f_lo=pp_params.get('f_lo', 4.0),
        f_hi=pp_params.get('f_hi', 38.0),
        iir_order=pp_params.get('iir_order', 4),
        exp_alpha=pp_params.get('exp_alpha', 0.001),
        exp_init=pp_params.get('exp_init', 1000)
    )
    
    wc_params = bci_config.get_window_params()
    wc = WindowConfig(
        win_start=wc_params.get('win_start', 0.5),
        win_stop=wc_params.get('win_stop', 3.0)
    )
    
    tr_params = bci_config.get_training_params()
    tr = TrainConfig(
        epochs=args.epochs if args.epochs is not None else tr_params.get('epochs', 5),
        batch_size=tr_params.get('batch_size', 64),
        lr=tr_params.get('lr', 1e-4),
        freeze_features=tr_params.get('freeze_features', False),
        early_stop_patience=args.patience if args.patience is not None else tr_params.get('early_stop_patience', 3)
    )
    
    # Generate session directory based on subject ID and timestamp
    if args.subject:
        from datetime import datetime
        timestamp = datetime.now().strftime("%Y-%m-%d_%H-%M")
        session_name = f"session_{timestamp}"
        session_dir = os.path.join("data", args.subject, session_name)
        calib_npz = os.path.join(session_dir, "calib_windows.npz")
        finetuned_pt = os.path.join(session_dir, "finetuned.pt")
        finetuned_onnx = os.path.join(session_dir, "finetuned.onnx")
    else:
        session_dir = "./session_stage2"
        calib_npz = "./session_stage2/calib_windows.npz"
        finetuned_pt = "./session_stage2/finetuned.pt"
        finetuned_onnx = "./session_stage2/finetuned.onnx"
    
    paths = Paths(session_dir=session_dir,
                  calib_npz=calib_npz,
                  finetuned_pt=finetuned_pt,
                  finetuned_onnx=finetuned_onnx,
                  PRETRAINED_CKPT=args.pretrained)

    os.makedirs(paths.session_dir, exist_ok=True)
    engine = Stage2Engine(lsl, td, pp, wc, tr, paths, bci_config)

    # ========== Modes ==========
    if args.mode == 'ui_only':
        print("[Mode] UI ONLY – no LSL, no model")
        marker = MarkerOutlet("Markers")
        ui = StimUI(td, marker, bci_config, use_feedback=True)
        print("=== TEST 1: Calibration sequence ===")
        ui.run_calibration()
        print("=== TEST 2: Random feedback sequence ===")
        n_classes = bci_config.n_classes
        ui.run_online_feedback(lambda: tuple(random.random() for _ in range(n_classes)), n_trials_each=5)
        return

    if args.mode == 'eeg_only':
        print("[Mode] EEG ONLY – LSL I/O, no model/feedback")
        engine.start_eeg_pipeline()
        engine.inspect_channels()
        marker = engine.marker
        ui = StimUI(td, marker, bci_config, use_feedback=False)
        print("=== Running calibration to verify markers & timing (no training) ===")
        _ = ui.run_calibration()
        print("Done. EEG stream/markers verified.")
        return

    if args.mode == 'sim_eeg_model':
        print("[Mode] SIM EEG + MODEL – virtual EEG stream + training + feedback")
        # start virtual EEG
        vout = VirtualEEGOutlet(engine.marker, name=lsl.eeg_name, sf=pp.sfreq_target, get_side=engine._get_sim_side)
        vout.start()
        # start pipeline reading the virtual stream
        engine.start_eeg_pipeline()
        engine.inspect_channels()
        # build and (optionally) load pretrained model
        engine.build_model()
        ui = StimUI(td, engine.marker, bci_config, use_feedback=False)
        timeline = ui.run_calibration()
        X, y = engine.collect_calibration(timeline)
        engine.finetune(X, y)
        if args.export_onnx:
            engine.export_onnx()
        # feedback
        ui_fb = StimUI(td, engine.marker, bci_config, use_feedback=True)
        ui_fb.run_online_feedback(engine.online_probs, n_trials_each=10)
        vout.stop(); vout.join(timeout=2.0)
        engine.shutdown()
        return

    if args.mode == 'full':
        print("[Mode] FULL – real EEG + calibration + finetune + feedback")
        engine.start_eeg_pipeline()
        engine.inspect_channels()
        engine.build_model()
        ui = StimUI(td, engine.marker, bci_config, use_feedback=False)
        timeline = ui.run_calibration()
        X, y = engine.collect_calibration(timeline)
        engine.finetune(X, y)
        if args.export_onnx:
            engine.export_onnx()
        ui_fb = StimUI(td, engine.marker, bci_config, use_feedback=True)
        ui_fb.run_online_feedback(engine.online_probs, n_trials_each=20)
        engine.shutdown()
        return

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("Interrupted by user")
