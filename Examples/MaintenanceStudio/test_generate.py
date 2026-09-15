import copy
import tempfile
import unittest
from pathlib import Path
from generate import generate, validate, write_bundle


class GeneratorTests(unittest.TestCase):
    def test_reproducibility_and_reference_failures(self):
        rows = generate()
        self.assertEqual(sum(map(len, rows.values())), 1000)
        self.assertEqual(rows, generate())
        self.assertNotEqual(rows, generate(42))
        broken = copy.deepcopy(rows)
        broken['Sensor'][0]['equipmentID'] = 'missing'
        with self.assertRaises(KeyError):
            validate(broken)
        broken = copy.deepcopy(rows)
        broken['WorkOrder'][0]['factoryID'] = 'invalid'
        with self.assertRaises((KeyError, AssertionError)):
            validate(broken)
        with tempfile.TemporaryDirectory() as directory:
            first, second = Path(directory)/'first', Path(directory)/'second'
            write_bundle(first, 20260915)
            write_bundle(second, 20260915)
            for path in first.iterdir():
                self.assertEqual(path.read_bytes(), (second/path.name).read_bytes())
            with self.assertRaises(FileExistsError):
                write_bundle(first, 20260915)


if __name__ == '__main__':
    unittest.main()
