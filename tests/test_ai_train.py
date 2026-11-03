"""tools/ai_train.py: card-identity inputs (train --cards, docs/AI_OPPONENT.md §10). The card
one-hot is kept sparse in training; export writes it as dense input columns (mean 0, std 1)
and read_weights / average / ensemble take it back."""
import contextlib
import io
import re
import sys
import tempfile
import unittest
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import ai_train  # noqa: E402


def toy(n=6000, seed=0):
    """Two noise inputs; the target is a value per card (card 0: no card, value 0)."""
    rng = np.random.default_rng(seed)
    value = rng.normal(0, 10, ai_train.N_CARDS + 1)
    value[0] = 0
    cards = rng.integers(0, 30, n).astype(np.int16)        # 0 and cards 1..29
    x = rng.normal(0, 1, (n, 2)).astype(np.float32)
    y = value[cards].astype(np.float32)
    games = np.arange(n) // 20
    return x, y, cards, games


def quiet(fn, *args, **kw):
    with contextlib.redirect_stdout(io.StringIO()):
        return fn(*args, **kw)


class CardInputsTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.x, cls.y, cls.cards, cls.games = toy()
        cls.params, cls.mean, cls.std = quiet(ai_train.train, cls.x, cls.y, hidden=(16,), epochs=25, lr=3e-3,
                                              games=cls.games, cards=cls.cards)

    def predict(self, params, mean, std, cards):
        return ai_train.predict(params, (self.x - mean) / std, cards)

    def test_the_card_identity_is_learned(self):
        held = self.games % 10 == 0
        pred = self.predict(self.params, self.mean, self.std, self.cards)
        mse = float(np.mean((pred[held] - self.y[held]) ** 2))
        self.assertLess(mse, 0.05 * float(np.var(self.y[held])), "card inputs explain the target")
        # without the card inputs nothing predicts it
        p0, m0, s0 = quiet(ai_train.train, self.x, self.y, hidden=(16,), epochs=5, lr=3e-3, games=self.games)
        mse0 = float(np.mean((ai_train.predict(p0, (self.x[held] - m0) / s0) - self.y[held]) ** 2))
        self.assertGreater(mse0, 0.8 * float(np.var(self.y[held])))

    def test_export_and_read_weights_round_trip(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "cards.lua"
            quiet(ai_train.export, self.params, self.mean, self.std, out, "test.")
            text = out.read_text(encoding="utf-8")
            self.assertIn(f"  inputs = {2 + ai_train.N_CARDS},\n", text)
            self.assertIn(f"  cards = {ai_train.N_CARDS},\n", text)
            mean = [float(v) for v in re.search(r"mean = \{([^}]*)\}", text).group(1).split(",")]
            std = [float(v) for v in re.search(r"std = \{([^}]*)\}", text).group(1).split(",")]
            self.assertEqual(mean[2:], [0.0] * ai_train.N_CARDS, "card columns are not standardised")
            self.assertEqual(std[2:], [1.0] * ai_train.N_CARDS)
            self.assertIn(f"n_in = {2 + ai_train.N_CARDS}, n_out = 16", text)
            params, mean2, std2 = ai_train.read_weights(out)
            self.assertEqual(ai_train.card_count(params), ai_train.N_CARDS)
            self.assertEqual(len(mean2), 2)
            a = self.predict(self.params, self.mean, self.std, self.cards)
            b = self.predict(params, mean2, std2, self.cards)
            np.testing.assert_allclose(a, b, rtol=1e-3, atol=1e-3)
            # the dense one-hot through the exported first layer gives the same Q
            onehot = np.zeros((len(self.x), ai_train.N_CARDS), np.float32)
            some = self.cards > 0
            onehot[np.nonzero(some)[0], self.cards[some] - 1] = 1
            dense = [[np.vstack([params[0][0], params[0][2][1:]]), params[0][1]]] + params[1:]
            xn = np.hstack([(self.x - mean2) / std2, onehot])
            np.testing.assert_allclose(ai_train.predict(dense, xn), b, rtol=1e-6, atol=1e-6)

            # average of two snapshots of one run, ensemble mixing a card and a plain network
            quiet(ai_train.main, ["average", "--weights", str(out), "--weights", str(out),
                                  "--out", str(Path(tmp) / "avg.lua")])
            pa, ma, sa = ai_train.read_weights(Path(tmp) / "avg.lua")
            np.testing.assert_allclose(self.predict(pa, ma, sa, self.cards), b, rtol=1e-3, atol=1e-3)
            plain = Path(tmp) / "plain.lua"
            quiet(ai_train.export, [[np.ones((2, 1)), np.zeros(1)]], self.mean, self.std, plain, "plain.")
            self.assertNotIn("cards =", plain.read_text(encoding="utf-8"))
            ens = Path(tmp) / "ens.lua"
            quiet(ai_train.main, ["ensemble", "--weights", str(out), "--weights", str(plain), "--out", str(ens)])
            head = ens.read_text(encoding="utf-8").split("members = {")[0]
            self.assertIn("  inputs = 2,\n", head)
            self.assertIn(f"  cards = {ai_train.N_CARDS},\n", head)

    def test_load_reads_the_card_field(self):
        n = sum(ai_train.FEATURE_SIZES[1])
        row = ",".join(["0"] * n)
        lines = [f"D|1|Red|0|{row}|10|123", f"D|1|Red|2|{row}|12|0", f"D|1|Red|3|{row}|13",   # 6 fields: old
                 f"D|1|Red|3|0,1", "E|1|Red|5|win|20"]                                      # cut short
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "d.txt"
            path.write_text("\n".join(lines) + "\n", encoding="utf-8")
            x, y, games, nxt, cards = ai_train.load([path])
            self.assertEqual(list(cards), [123, 0, 0])
            self.assertEqual(x.shape, (3, n))
            spath = Path(tmp) / "s.txt"
            spath.write_text(f"S|1|Red|0|1|2.5|1|1|{row}|77\nS|1|Red|0|2|1.5|1|0|{row}\n", encoding="utf-8")
            sx, sy, sg, sc = ai_train.load_search([spath])
            self.assertEqual(list(sc), [77, 0])
            # field 11, the target: lines without it are margin; train --target must match
            ai_train.load_search([spath], target="margin")
            with self.assertRaises(SystemExit):
                ai_train.load_search([spath], target="score")
            spath.write_text(f"S|1|Red|0|1|2.5|1|1|{row}|77|score\n", encoding="utf-8")
            sx, sy, sg, sc = ai_train.load_search([spath], target="score")
            self.assertEqual(list(sc), [77])
            with self.assertRaises(SystemExit):
                ai_train.load_search([spath], target="margin")


if __name__ == "__main__":
    unittest.main()
