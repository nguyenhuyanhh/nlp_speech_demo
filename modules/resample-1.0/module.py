"""
Module: resample
Version: 1.0

Resample a file_id into /resample
"""

import os
import sys

from sox import Transformer

CUR_DIR = os.path.dirname(os.path.realpath(__file__))
ROOT_DIR = os.path.dirname(os.path.dirname(CUR_DIR))
DATA_DIR = os.path.join(ROOT_DIR, 'data/')


def resample(file_id):
    """Resample a file_id."""
    # init paths
    working_dir = os.path.join(DATA_DIR, file_id)
    raw_dir = os.path.join(working_dir, 'raw/')
    resample_dir = os.path.join(working_dir, 'resample/')
    if not os.path.exists(resample_dir):
        os.makedirs(resample_dir)

    # resample
    audio_in = os.path.join(raw_dir, os.listdir(raw_dir)[0])
    audio_out = os.path.join(resample_dir, '{}.wav'.format(file_id))
    tfm = Transformer()
    tfm.convert(samplerate=16000, n_channels=1, bitdepth=16)
    tfm.build(audio_in, audio_out)

if __name__ == '__main__':
    resample(sys.argv[1])