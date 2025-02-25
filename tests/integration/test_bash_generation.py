import os
import unittest


class TestBashGeneration(unittest.TestCase):
    def test_bash_generation(self):
        self.assertEqual(
            os.system("zppy -c tests/integration/test_bash_generation.cfg"), 0
        )
        self.assertEqual(
            os.system(
                "diff -bur -I 'templateDir' test_bash_generation_output/post/scripts /lcrc/group/e3sm/public_html/zppy_test_resources/expected_bash_files"
            ),
            0,
        )
        self.assertEqual(os.system("rm -r test_bash_generation_output"), 0)


if __name__ == "__main__":
    # Run from top level of repo
    unittest.main()
