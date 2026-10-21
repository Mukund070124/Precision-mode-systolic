
import random
import pandas as pd
from IPython.display import display

# ====================== SETTINGS ======================

# PRECISION MODE
# 0 = INT4   (00)   Values: -8 to +7
# 1 = INT8   (01)   Values: -128 to +127
# 2 = INT16  (10)   Values: -32768 to +32767
# 3 = ALL THREE MODES

MODE_NUMBER = 0


# CORNER CASE SELECTION
# 0  = Zero x Zero
# 1  = Identity x Matrix
# 2  = Matrix x Identity
# 3  = Maximum x Maximum
# 4  = Minimum x Minimum
# 5  = Minimum x Maximum
# 6  = Maximum x Minimum
# 7  = Alternating Signs
# 8  = Sparse Matrix
# 9  = Random Signed
# 10 = ALL TEN CORNER CASES

CASE_NUMBER = 1


# DISPLAY OPTIONS
SHOW_MATRICES = True
SHOW_CLOCK_MATRIX = True
SHOW_EACH_CLOCK = False

# ======================================================

N = 16

MODES = {
    0: ("00", 4),
    1: ("01", 8),
    2: ("10", 16)
}

ACC_WIDTHS = {
    4: 12,
    8: 20,
    16: 36
}

CASE_NAMES = {
    0: "Zero x Zero",
    1: "Identity x Matrix",
    2: "Matrix x Identity",
    3: "Maximum x Maximum",
    4: "Minimum x Minimum",
    5: "Minimum x Maximum",
    6: "Maximum x Minimum",
    7: "Alternating Signs",
    8: "Sparse Matrix",
    9: "Random Signed"
}


# ============ DISPLAY MATRIX ============

def show_matrix(name, matrix):

    print(f"\n{name} (16 x 16)")

    df = pd.DataFrame(
        matrix,
        index=[f"Row {i}" for i in range(N)],
        columns=[f"Col {j}" for j in range(N)]
    )

    display(df)


# ============ GENERATE CORNER CASES ============

def make_corner_case(case_number, bits):

    minimum = -(1 << (bits - 1))
    maximum = (1 << (bits - 1)) - 1

    rng = random.Random(2026 + bits)

    Z = [[0] * N for _ in range(N)]

    I = [
        [int(i == j) for j in range(N)]
        for i in range(N)
    ]

    A_random = [
        [rng.randint(minimum, maximum) for _ in range(N)]
        for _ in range(N)
    ]

    B_random = [
        [rng.randint(minimum, maximum) for _ in range(N)]
        for _ in range(N)
    ]

    def uniform(value):
        return [[value] * N for _ in range(N)]

    if case_number == 0:
        return Z, Z

    elif case_number == 1:
        return I, B_random

    elif case_number == 2:
        return A_random, I

    elif case_number == 3:
        return uniform(maximum), uniform(maximum)

    elif case_number == 4:
        return uniform(minimum), uniform(minimum)

    elif case_number == 5:
        return uniform(minimum), uniform(maximum)

    elif case_number == 6:
        return uniform(maximum), uniform(minimum)

    elif case_number == 7:

        alternating = [
            [
                minimum if (i + j) % 2 == 0 else maximum
                for j in range(N)
            ]
            for i in range(N)
        ]

        return alternating, alternating

    elif case_number == 8:

        A = [[0] * N for _ in range(N)]
        B = [[0] * N for _ in range(N)]

        A[0][0] = minimum
        B[0][0] = maximum

        return A, B

    elif case_number == 9:
        return A_random, B_random

    else:
        raise ValueError("Invalid corner case")


# ============ GOLDEN MATRIX RESULT ============

def golden_result(A, B):

    C = [[0] * N for _ in range(N)]

    for i in range(N):
        for j in range(N):
            for k in range(N):
                C[i][j] += A[i][k] * B[k][j]

    return C


# ============ SYSTOLIC CLOCK SIMULATION ============

def simulate_systolic(A, B, acc_width):

    # Operand forwarding registers
    a_reg = [[None] * N for _ in range(N)]
    b_reg = [[None] * N for _ in range(N)]

    # 256 PE accumulators
    acc = [[0] * N for _ in range(N)]

    # Number of MAC operations completed by each PE
    count = [[0] * N for _ in range(N)]

    # Final output-ready clock
    ready_clock = [[None] * N for _ in range(N)]

    # Results completed at each clock
    completed = [[] for _ in range(46)]

    min_acc = -(1 << (acc_width - 1))
    max_acc = (1 << (acc_width - 1)) - 1

    # 46 clock edges
    for t in range(46):

        next_a = [[None] * N for _ in range(N)]
        next_b = [[None] * N for _ in range(N)]

        for i in range(N):
            for j in range(N):

                ka = t - i
                kb = t - j

                # A moves left to right
                if j == 0:
                    if 0 <= ka < N:
                        a = (A[i][ka], ka)
                    else:
                        a = None
                else:
                    a = a_reg[i][j - 1]

                # B moves top to bottom
                if i == 0:
                    if 0 <= kb < N:
                        b = (B[kb][j], kb)
                    else:
                        b = None
                else:
                    b = b_reg[i - 1][j]

                # Values forwarded for next clock
                next_a[i][j] = a
                next_b[i][j] = b

                # MAC only when valid operands arrive
                if a is not None and b is not None:

                    assert a[1] == b[1], "Operand alignment error"

                    k = a[1]

                    assert t == i + j + k

                    product = a[0] * b[0]

                    acc[i][j] += product

                    count[i][j] += 1

                    # Verify signed accumulator range
                    assert min_acc <= acc[i][j] <= max_acc, (
                        "Accumulator overflow"
                    )

                    # Final output after 16 MACs
                    if count[i][j] == 16:

                        ready_clock[i][j] = t + 1

                        completed[t].append(
                            (i, j, acc[i][j])
                        )

        # Simultaneous register update
        a_reg = next_a
        b_reg = next_b

    return acc, count, ready_clock, completed


# ============ VERIFY ONE CASE ============

def run_one(mode_number, case_number):

    mode, bits = MODES[mode_number]

    # Generate 16x16 matrices
    A, B = make_corner_case(case_number, bits)

    # Independent mathematical answer
    expected = golden_result(A, B)

    # Clock-by-clock systolic answer
    actual, count, ready, completed = simulate_systolic(
        A, B, ACC_WIDTHS[bits]
    )

    # Verify all 256 elements
    assert actual == expected, "Matrix multiplication mismatch"

    # Verify 16 MACs per PE
    for i in range(N):
        for j in range(N):

            assert count[i][j] == 16, "MAC count error"

            assert ready[i][j] == i + j + 16, (
                "Output clock error"
            )

    # Extra identity checks
    if case_number == 1:
        assert actual == B

    if case_number == 2:
        assert actual == A

    print("\n" + "=" * 65)
    print(f"MODE {mode} : INT{bits}")
    print(f"CORNER CASE {case_number}: {CASE_NAMES[case_number]}")
    print("=" * 65)

    # Optional clock-wise output
    if SHOW_EACH_CLOCK:

        for clock, results in enumerate(completed, start=1):

            if results:

                text = ", ".join(
                    f"C[{i}][{j}]={value}"
                    for i, j, value in results
                )

                print(f"Clock {clock:2d}: {text}")

            else:
                print(f"Clock {clock:2d}: No final output")

    # Display complete input/output matrices
    if SHOW_MATRICES:

        show_matrix("Input Matrix A", A)

        show_matrix("Input Matrix B", B)

        show_matrix("Output Matrix C = A x B", actual)

    # Display clock matrix
    if SHOW_CLOCK_MATRIX:

        show_matrix("Output Ready Clock", ready)

    print("\nPASS: All 256 outputs correct")
    print("Every PE completed 16 MAC operations")
    print("First final output: Clock 16")
    print("Last final output: Clock 46")


# ============ MAIN PROGRAM ============

def main():

    if MODE_NUMBER not in (0, 1, 2, 3):
        raise ValueError("MODE_NUMBER must be 0, 1, 2 or 3")

    if CASE_NUMBER not in range(11):
        raise ValueError("CASE_NUMBER must be 0 to 10")

    if MODE_NUMBER == 3:
        selected_modes = [0, 1, 2]
    else:
        selected_modes = [MODE_NUMBER]

    if CASE_NUMBER == 10:
        selected_cases = range(10)
    else:
        selected_cases = [CASE_NUMBER]

    total_tests = 0

    for mode_number in selected_modes:

        for case_number in selected_cases:

            run_one(mode_number, case_number)

            total_tests += 1

    print("\n" + "=" * 65)
    print("ALL SELECTED CORNER CASES PASSED")
    print("Total matrix tests:", total_tests)
    print("Total output comparisons:", total_tests * 256)
    print("=" * 65)


main()
