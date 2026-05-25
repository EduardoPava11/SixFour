//! viz — DEV/PROTOTYPE visualizer (not the shipped product UI; the product is
//! bespoke egui). Loads a 64³ GIF via `analysis-core`, positions its 256
//! colours in perceptual OKLab space, and logs them to the Rerun native viewer:
//! orbit the cube, scrub/play the 64 frames, watch the colours ride their
//! delta-trails.
//!
//!   cargo run -p viz -- --gif path/to.gif      # real GIF
//!   cargo run -p viz                           # synthetic fixture
//!
//! Writes `sixfour_palette_deltas.rrd`; open with the bundled viewer:
//!   ./.venv/bin/rerun sixfour_palette_deltas.rrd

use analysis_core::{color::oklab_to_srgb8, load_stack, synthetic_stack, CyclicStack, Oklab};
use rerun::{Color, LineStrips3D, Points3D, RecordingStreamBuilder};

/// OKLab → a centred cube position (L vertical; a,b the opponent axes).
fn pos(c: Oklab) -> [f32; 3] {
    [(c[1] * 3.0) as f32, ((c[0] - 0.5) * 3.0) as f32, (c[2] * 3.0) as f32]
}

fn rgb(c: Oklab) -> Color {
    let s = oklab_to_srgb8(c);
    Color::from_rgb(s[0], s[1], s[2])
}

/// Per-frame max-normalised population → concentration in 0..1.
fn concentration(weights: &[f64]) -> Vec<f64> {
    let mx = weights.iter().cloned().fold(0.0_f64, f64::max).max(1e-9);
    weights.iter().map(|&w| w / mx).collect()
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args: Vec<String> = std::env::args().collect();

    // Dev affordance: write a real 64×64×64 sample GIF and exit.
    if let Some(i) = args.iter().position(|a| a == "--make-sample") {
        let out = args.get(i + 1).map(|s| s.as_str()).unwrap_or("sample.gif");
        analysis_core::write_sample_gif(out, 64)?;
        println!("wrote sample GIF: {out}");
        return Ok(());
    }

    let gif_path = args.iter().position(|a| a == "--gif").and_then(|i| args.get(i + 1));

    let stack: CyclicStack = match gif_path {
        Some(p) => {
            eprintln!("loading GIF: {p}");
            load_stack(p)?
        }
        None => {
            eprintln!("no --gif given; using synthetic 64×256 fixture");
            synthetic_stack(64, 256)
        }
    };
    let t = stack.frames.len();
    let k = stack.frames.first().map(|f| f.palette.len()).unwrap_or(0);
    eprintln!("stack: {t} frames × {k} colours");

    let rec = RecordingStreamBuilder::new("sixfour_palette_deltas")
        .save("sixfour_palette_deltas.rrd")?;

    // --- static delta-trails: each colour's closed loop over the frames ---
    let mut strips: Vec<Vec<[f32; 3]>> = Vec::with_capacity(k);
    let mut strip_cols: Vec<Color> = Vec::with_capacity(k);
    for ci in 0..k {
        let mut s: Vec<[f32; 3]> = (0..t).map(|tt| pos(stack.frames[tt].palette[ci])).collect();
        if let Some(&first) = s.first() {
            s.push(first); // close the loop
        }
        strips.push(s);
        strip_cols.push(rgb(stack.frames[0].palette[ci]));
    }
    rec.log_static(
        "delta_trails",
        &LineStrips3D::new(strips).with_colors(strip_cols).with_radii([0.0015_f32]),
    )?;

    // --- animated points: the 256 colours at each frame ---
    for (tt, frame) in stack.frames.iter().enumerate() {
        rec.set_time_sequence("frame", tt as i64);
        let conc = concentration(&frame.weights);
        let positions: Vec<[f32; 3]> = frame.palette.iter().map(|&c| pos(c)).collect();
        let colors: Vec<Color> = frame.palette.iter().map(|&c| rgb(c)).collect();
        let radii: Vec<f32> = conc.iter().map(|&w| (0.012 + 0.05 * w) as f32).collect();
        rec.log(
            "colors",
            &Points3D::new(positions).with_colors(colors).with_radii(radii),
        )?;
    }

    println!("wrote sixfour_palette_deltas.rrd ({t}×{k}). View: ./.venv/bin/rerun sixfour_palette_deltas.rrd");
    Ok(())
}
