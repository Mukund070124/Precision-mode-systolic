"""Colab-friendly 16x16 systolic matrix multiplication golden model.
Mode 00=INT4, 01=INT8, 10=INT16. First processed clock is Clock 1.
"""
import random

N = 16
MODE = "00"            # Change to "01", "10", or "all"
SEED = 7
SHOW_MATRICES = False  # True to print the entire A, B and C matrices


def print_matrix(name, matrix):
    print(f"{name} (16x16):")
    for row in matrix:
        print(" ".join(f"{x:8d}" for x in row))


def run(mode):
    bits = {"00": 4, "01": 8, "10": 16}[mode]
    rng = random.Random(SEED)
    low, high = -(1 << (bits - 1)), (1 << (bits - 1)) - 1
    A = [[rng.randint(low, high) for _ in range(N)] for _ in range(N)]
    B = [[rng.randint(low, high) for _ in range(N)] for _ in range(N)]

    # Each PE has an accumulator and two forwarding registers.
    acc = [[0] * N for _ in range(N)]
    count = [[0] * N for _ in range(N)]
    a_reg = [[None] * N for _ in range(N)]
    b_reg = [[None] * N for _ in range(N)]

    print(f"\nMODE {mode}: signed INT{bits}, operand range {low} to {high}")
    if SHOW_MATRICES:
        print_matrix("A", A)
        print_matrix("B", B)

    for t in range(46):  # t=0..45 means displayed Clock 1..46.
        next_a = [[None] * N for _ in range(N)]
        next_b = [[None] * N for _ in range(N)]
        finished = []

        for i in range(N):
            for j in range(N):
                # Input skew: A enters row i starting at t=i.
                ka = t - i
                a = ((A[i][ka], ka) if 0 <= ka < N else None) if j == 0 else a_reg[i][j-1]

                # Input skew: B enters column j starting at t=j.
                kb = t - j
                b = ((B[kb][j], kb) if 0 <= kb < N else None) if i == 0 else b_reg[i-1][j]

                # Each forwarded operand becomes visible to the NEXT PE next clock.
                next_a[i][j] = a
                next_b[i][j] = b

                if a is not None and b is not None:
                    assert a[1] == b[1], "Operand alignment error"
                    acc[i][j] += a[0] * b[0]
                    count[i][j] += 1
                    if count[i][j] == N:
                        finished.append((i, j, acc[i][j]))

        a_reg, b_reg = next_a, next_b
        if finished:
            output_text = ", ".join(f"C[{i}][{j}]={value}" for i, j, value in finished)
            print(f"Clock {t+1:2d}: {output_text}")
        else:
            print(f"Clock {t+1:2d}: No final outputs yet")

    golden = [[sum(A[i][k] * B[k][j] for k in range(N))
               for j in range(N)] for i in range(N)]
    assert all(count[i][j] == 16 for i in range(N) for j in range(N))
    assert acc == golden, "Systolic outputs differ from golden matrix multiplication!"
    print("\n" + "=" * 70)
    print("FINAL MATRIX MULTIPLICATION RESULT")
    print("=" * 70)

    print_matrix("Input Matrix A", A)
    print_matrix("Input Matrix B", B)
    print_matrix("Output Matrix C = A x B", acc)
    if SHOW_MATRICES:
        print_matrix("C=A*B", acc)
    print(f"PASS: all 256 outputs verified in INT{bits} (last output at clock 46).")
    return A, B, acc


if MODE == "all":
    for selected_mode in ("00", "01", "10"):
        run(selected_mode)
else:
    run(MODE)
