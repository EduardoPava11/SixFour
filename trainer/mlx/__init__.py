"""SixFour H-JEPA trainer (v1 floor): the frozen zero-param encoder + the 63-param
theta_B masked-band predictor, trained byte-exact against the Haskell spec goldens.

Module roster (each a byte-exact twin of a spec/SixFour/Spec module):
  q16                  - the float->byte Q16 crossing (Q16.hs / ByteCarrier.hs)
  encoder_frozen       - the zero-param feature map (EncoderFrozen.hs)
  theta_b              - the 63-param predictor forward (MaskedBandPrediction.hs)
  jepa_loss            - masked-band loss + exact gradient (MaskedBandPrediction.hs)
  masked_band_trainer  - the training gate, reproduces goldenTrainedBand (MaskedBandTrainer.hs)
  autograd_check       - MLX autodiff == analytic gradient (the scale-up bridge)

Run the whole gate: `python gate_trainer.py`.
"""
