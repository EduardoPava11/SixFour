//! GIF I/O: decode a real 64³ GIF into a `CyclicStack` (per-frame palette →
//! OKLab, concentration = real per-colour pixel population from the index
//! histogram), plus a synthetic fixture + sample-GIF writer for tests/`viz`
//! before a device GIF is supplied.

use std::borrow::Cow;
use std::fs::File;

use crate::color::srgb8_to_oklab;
use crate::cyclic::{CyclicStack, Frame};

type Err = Box<dyn std::error::Error>;

const K: usize = 256;

/// Decode a GIF → `CyclicStack`. Each frame's palette (local, else global) is
/// padded to `K` OKLab colours; weights are the per-colour pixel counts.
pub fn load_stack(path: &str) -> Result<CyclicStack, Err> {
    let mut opts = gif::DecodeOptions::new();
    opts.set_color_output(gif::ColorOutput::Indexed);
    let mut decoder = opts.read_info(File::open(path)?)?;
    let global: Option<Vec<u8>> = decoder.global_palette().map(|p| p.to_vec());

    let mut frames = Vec::new();
    while let Some(frame) = decoder.read_next_frame()? {
        let pal_bytes = frame
            .palette
            .clone()
            .or_else(|| global.clone())
            .ok_or("GIF frame has neither a local nor a global palette")?;
        let ncols = pal_bytes.len() / 3;
        let palette = (0..K)
            .map(|i| {
                let c = if i < ncols {
                    [pal_bytes[i * 3], pal_bytes[i * 3 + 1], pal_bytes[i * 3 + 2]]
                } else {
                    [0, 0, 0]
                };
                srgb8_to_oklab(c)
            })
            .collect();
        let mut weights = vec![0.0_f64; K];
        for &ix in frame.buffer.iter() {
            let idx = ix as usize;
            if idx < K {
                weights[idx] += 1.0;
            }
        }
        frames.push(Frame { palette, weights });
    }
    Ok(CyclicStack { frames })
}

/// Synthetic drifting palette (6 colour clusters orbiting the cube), sRGB.
pub fn synth_color(t: usize, i: usize, t_count: usize) -> [u8; 3] {
    let u = (t as f64) / (t_count as f64) * std::f64::consts::TAU;
    let cl = (i % 6) as f64;
    let r = (0.5 + 0.4 * (u + cl).sin()).clamp(0.0, 1.0);
    let g = (0.5 + 0.4 * (u * 2.0 + cl * 1.7).sin()).clamp(0.0, 1.0);
    let b = (0.5 + 0.4 * (u + cl * 0.5 + (i as f64) * 0.01).cos()).clamp(0.0, 1.0);
    [(r * 255.0) as u8, (g * 255.0) as u8, (b * 255.0) as u8]
}

/// A synthetic `CyclicStack` for tests/fallback (non-uniform weights so the
/// `S_K`-invariance test is non-trivial).
pub fn synthetic_stack(t_count: usize, k: usize) -> CyclicStack {
    let frames = (0..t_count)
        .map(|t| {
            let palette = (0..k).map(|i| srgb8_to_oklab(synth_color(t, i, t_count))).collect();
            let weights = (0..k).map(|i| 1.0 + ((i * 31) % 13) as f64).collect();
            Frame { palette, weights }
        })
        .collect();
    CyclicStack { frames }
}

/// Write a real 64×64×`t_count` GIF (per-frame local palettes, surjective
/// index buffer) so the full decode path can be exercised end-to-end.
pub fn write_sample_gif(path: &str, t_count: usize) -> Result<(), Err> {
    let mut file = File::create(path)?;
    let mut encoder = gif::Encoder::new(&mut file, 64, 64, &[])?;
    encoder.set_repeat(gif::Repeat::Infinite)?;
    for t in 0..t_count {
        let mut palette = Vec::with_capacity(K * 3);
        for i in 0..K {
            palette.extend_from_slice(&synth_color(t, i, t_count));
        }
        // First 256 pixels hit every index (surjective); the rest concentrate
        // into a prime range so the population distribution is non-uniform.
        let mut buffer = vec![0u8; 64 * 64];
        for (p, slot) in buffer.iter_mut().enumerate() {
            *slot = if p < K { p as u8 } else { ((p * p) % 251) as u8 };
        }
        let mut frame = gif::Frame::default();
        frame.width = 64;
        frame.height = 64;
        frame.palette = Some(palette);
        frame.buffer = Cow::Owned(buffer);
        encoder.write_frame(&frame)?;
    }
    Ok(())
}
