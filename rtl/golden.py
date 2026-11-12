#!/usr/bin/env python3
"""systolic2x2 golden model.

Independent matmul, hand-computed asserts, a cycle-level systolic model
(checks the SPEC timing table) and vector generation.
Usage: python3 golden.py <outdir>   (default: .)
"""
import os
import random
import sys


def matmul(A, B):
    C = []
    for i in range(2):
        row = []
        for j in range(2):
            row.append(A[i][0] * B[0][j] + A[i][1] * B[1][j])
        C.append(row)
    return C


def flat(M):
    return [M[0][0], M[0][1], M[1][0], M[1][1]]


def hand_asserts():
    """Expected values are hand-computed literals, not produced by matmul()."""
    I = [[1, 0], [0, 1]]
    Z = [[0, 0], [0, 0]]
    Bm = [[5, -6], [7, 8]]
    P = [[127, 127], [127, 127]]
    N = [[-128, -128], [-128, -128]]
    checks = []
    # 1 identity
    checks.append(matmul(I, Bm) == Bm)
    # 2 zero matrix on both sides
    checks.append(matmul(Z, Bm) == Z and matmul(Bm, Z) == Z)
    # 3 all 127: 2*127*127 = 32258
    checks.append(matmul(P, P) == [[32258, 32258], [32258, 32258]])
    # 4 all -128: 2*128*128 = 32768
    checks.append(matmul(N, N) == [[32768, 32768], [32768, 32768]])
    # 5 127 x -128: 2*127*(-128) = -32512
    checks.append(matmul(P, N) == [[-32512, -32512], [-32512, -32512]])
    # 6 textbook example
    checks.append(matmul([[1, 2], [3, 4]], [[5, 6], [7, 8]]) == [[19, 22], [43, 50]])
    # 7 mixed sign
    checks.append(matmul([[-1, 2], [3, -4]], [[5, -6], [-7, 8]]) == [[-19, 22], [43, -50]])
    for i in range(len(checks)):
        assert checks[i], "hand assert %d failed" % (i + 1)
    return len(checks)


def build_inputs(groups, first_cycles):
    inp = dict()
    for g in range(len(groups)):
        A, B = groups[g]
        t0 = first_cycles[g]
        for k in range(2):
            inp[t0 + k] = (A[0][k], A[1][k], B[k][0], B[k][1])
    return inp


def cycle_model(groups, first_cycles, ncyc):
    """Cycle-level model of SPEC section 4.

    Returns {cycle: C(flat)} for the cycles where out_valid = 1.
    """
    inp = build_inputs(groups, first_cycles)
    acc = [0, 0, 0, 0]
    ar00 = ar10 = br00 = br01 = a1d = b1d = 0
    phase = 0
    f1 = l1 = f2 = l2 = 0
    ov = 0
    out = dict()
    for t in range(ncyc):
        if ov:
            out[t] = list(acc)
        if t in inp:
            v = 1
            a0, a1, b0, b1 = inp[t]
        else:
            v = 0
            a0 = a1 = b0 = b1 = 0
        f0 = 1 if (v and phase == 0) else 0
        l0 = 1 if (v and phase == 1) else 0
        pe_in = [(a0, b0, f0, l0), (ar00, b1d, f1, l1), (a1d, br00, f1, l1), (ar10, br01, f2, l2)]
        nacc = list(acc)
        for i in range(4):
            ai, bi, f, l = pe_in[i]
            if f or l:
                base = 0 if f else acc[i]
                nacc[i] = base + ai * bi
        n_ar10 = pe_in[2][0]
        n_br01 = pe_in[1][1]
        ov = l2
        f2, l2, f1, l1 = f1, l1, f0, l0
        if v:
            phase ^= 1
        acc = nacc
        ar00, br00, ar10, br01, a1d, b1d = a0, b0, n_ar10, n_br01, a1, b1
    return out


def wrap32(x):
    return x & 0xFFFFFFFF


def make_groups():
    I = [[1, 0], [0, 1]]
    Z = [[0, 0], [0, 0]]
    P = [[127, 127], [127, 127]]
    N = [[-128, -128], [-128, -128]]
    M1 = [[-1, -1], [-1, -1]]
    B1 = [[5, -6], [7, 8]]
    directed = [
        ("all127", P, P),
        ("all-128", N, N),
        ("127x-128", P, N),
        ("-128x127", N, P),
        ("I_x_B", I, B1),
        ("A_x_I", [[-9, 10], [11, -12]], I),
        ("I_x_I", I, I),
        ("zero_x_B", Z, B1),
        ("A_x_zero", B1, Z),
        ("zero_x_zero", Z, Z),
        ("mixed_sign", [[-1, 2], [3, -4]], [[5, -6], [-7, 8]]),
        ("textbook", [[1, 2], [3, 4]], [[5, 6], [7, 8]]),
        ("checker_ext", [[127, -128], [-128, 127]], [[-128, 127], [127, -128]]),
        ("rowext", [[127, 127], [-128, -128]], [[127, -128], [127, -128]]),
        ("neg1", M1, M1),
        ("max_neg_mix", [[-128, 127], [127, -128]], [[-128, 127], [127, -128]]),
    ]
    groups = list(directed)
    rng = random.Random(20261111)
    for i in range(64):
        A = [[rng.randint(-128, 127) for _ in range(2)] for _ in range(2)]
        B = [[rng.randint(-128, 127) for _ in range(2)] for _ in range(2)]
        groups.append(("rand%02d" % i, A, B))
    return groups, len(directed)


def write_vectors(outdir, groups):
    os.makedirs(outdir, exist_ok=True)
    rows = []
    for name, A, B in groups:
        rows.append((name, flat(A) + flat(B) + flat(matmul(A, B))))
    f = open(os.path.join(outdir, "vectors.txt"), "w")
    f.write("# name A00 A01 A10 A11 B00 B01 B10 B11 C00 C01 C10 C11 (decimal); seed=20261111\n")
    for name, cols in rows:
        f.write("%s %s\n" % (name, " ".join(str(c) for c in cols)))
    f.close()
    # 12 words per group: A(4) B(4) C(4), for $readmemh
    f = open(os.path.join(outdir, "vectors.hex"), "w")
    for name, cols in rows:
        for v in cols:
            f.write("%08x\n" % wrap32(v))
    f.close()


def main():
    outdir = sys.argv[1] if len(sys.argv) > 1 else "."
    print("hand asserts passed:", hand_asserts())
    groups, ndir = make_groups()
    assert len(groups) >= 60
    ab = [(g[1], g[2]) for g in groups]
    n = len(ab)
    # II=4 (minimum spacing): out_valid expected at cycle 4g+4
    out = cycle_model(ab, [4 * g for g in range(n)], 4 * n + 8)
    assert sorted(out) == [4 * g + 4 for g in range(n)], "out_valid mismatch"
    for g in range(n):
        assert out[4 * g + 4] == flat(matmul(ab[g][0], ab[g][1])), "group %d" % g
    print("cycle model == matmul and SPEC timing for %d groups (II=4)" % n)
    out2 = cycle_model(ab[:10], [7 * g for g in range(10)], 80)
    assert sorted(out2) == [7 * g + 4 for g in range(10)]
    for g in range(10):
        assert out2[7 * g + 4] == flat(matmul(ab[g][0], ab[g][1]))
    print("sparse spacing (II=7) also consistent")
    write_vectors(outdir, groups)
    print("vectors written: %d groups (%d directed + 64 random, seed 20261111)" % (n, ndir))


if __name__ == "__main__":
    main()
