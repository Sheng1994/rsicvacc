import pathlib
import unittest


class RepositorySkeletonTest(unittest.TestCase):
    def test_required_directories_exist(self):
        root = pathlib.Path(__file__).resolve().parents[2]
        for directory in ("rtl", "sim", "sw", "scripts", "docs", "fpga"):
            with self.subTest(directory=directory):
                self.assertTrue((root / directory).is_dir())

    def test_required_build_entry_points_exist(self):
        root = pathlib.Path(__file__).resolve().parents[2]
        makefile = (root / "Makefile").read_text(encoding="utf-8")
        for target in (
            "help", "lint", "test-unit", "test-core", "test-sw",
            "regression", "wave", "synth-yosys", "clean",
        ):
            with self.subTest(target=target):
                self.assertIn(f"{target}:", makefile)


if __name__ == "__main__":
    unittest.main()
