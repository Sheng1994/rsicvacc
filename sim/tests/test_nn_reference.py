import pathlib
import sys
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
from generate_nn_vectors import model  # noqa: E402


class NNReferenceTest(unittest.TestCase):
    def test_directed_reference_values(self):
        self.assertEqual(model(0, 0x04FD02FF, 0x08070605, 0, 0, 0), 18)
        self.assertEqual(model(1, 0xFFFFFFFB, 0, 0, 0, 0), 0)
        self.assertEqual(model(2, 200, 0, 0, 0, 0), 127)
        self.assertEqual(model(2, -200, 0, 0, 0, 0), (-128) & 0xFFFFFFFF)
        self.assertEqual(model(3, 0xFBFFFEF8, 0, 0, 0, 0), 0xFFFFFFFF)
        self.assertEqual(model(4, 5, 0, 3, 1, -2), 6)

    def test_requant_ties_away_from_zero(self):
        self.assertEqual(model(4, 1, 0, 3, 1, 0), 2)
        self.assertEqual(model(4, -1, 0, 3, 1, 0), 0xFFFFFFFE)
