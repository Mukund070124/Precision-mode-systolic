
import random

N = 16

MODES = {
    "00": 4,
    "01": 8,
    "10": 16
}

ACC_WIDTHS = {
    4: 12,
    8: 20,
    16: 36
}


# Independent golden reference
def golden_result(A, B):
    return [
        [
            sum(A[i][k] * B[k][j] for k in range(N))
            for j in range(N)
        ]
        for i in range(N)
    ]


# Clock-by-clock systolic model
def simulate_pe_array(A, B):

    a_reg = [[None] * N for _ in range(N)]
    b_reg = [[None] * N for _ in range(N)]

    acc = [[0] * N for _ in range(N)]
    counts = [[0] * N for _ in range(N)]
    ready_clock = [[None] * N for _ in range(N)]

    for t in range(46):

        next_a = [[None] * N for _ in range(N)]
        next_b = [[None] * N for _ in range(N)]

        for i in range(N):
            for j in range(N):

                ka = t - i
                kb = t - j

                if j == 0:
                    a = (A[i][ka], ka) if 0 <= ka < N else None
                else:
                    a = a_reg[i][j - 1]

                if i == 0:
                    b = (B[kb][j], kb) if 0 <= kb < N else None
                else:
                    b = b_reg[i - 1][j]

                next_a[i][j] = a
                next_b[i][j] = b

                if a is not None and b is not None:

                    assert a[1] == b[1], "Operand alignment error"

                    k = a[1]
                    assert t == i + j + k, "Clock scheduling error"

                    acc[i][j] += a[0] * b[0]
                    counts[i][j] += 1

                    if counts[i][j] == 16:
                        ready_clock[i][j] = t + 1

        a_reg = next_a
        b_reg = next_b

    return acc, counts, ready_clock


def corner_cases(bits):

    low = -(1 << (bits - 1))
    high = (1 << (bits - 1)) - 1

    Z = [[0] * N for _ in range(N)]

    I = [
        [int(i == j) for j in range(N)]
        for i in range(N)
    ]

    def uniform(value):
        return [[value] * N for _ in range(N)]

    rng = random.Random(2026 + bits)

    A = [
        [rng.randint(low, high) for _ in range(N)]
        for _ in range(N)
    ]

    B = [
        [rng.randint(low, high) for _ in range(N)]
        for _ in range(N)
    ]

    alternating = [
        [low if (i + j) % 2 == 0 else high
         for j in range(N)]
        for i in range(N)
    ]

    sparse_A = [[0] * N for _ in range(N)]
    sparse_B = [[0] * N for _ in range(N)]

    sparse_A[0][0] = low
    sparse_B[0][0] = high

    return [
        ("Zero x Zero", Z, Z),
        ("Identity x Matrix", I, A),
        ("Matrix x Identity", A, I),
        ("Maximum x Maximum", uniform(high), uniform(high)),
        ("Minimum x Minimum", uniform(low), uniform(low)),
        ("Minimum x Maximum", uniform(low), uniform(high)),
        ("Maximum x Minimum", uniform(high), uniform(low)),
        ("Alternating Signs", alternating, alternating),
        ("Sparse Matrix", sparse_A, sparse_B),
        ("Random Signed", A, B)
    ]


def verify_all():

    total_tests = 0
    total_outputs = 0

    for mode, bits in MODES.items():

        acc_width = ACC_WIDTHS[bits]

        print("\n" + "=" * 65)
        print(f"MODE {mode} : INT{bits}")
        print("=" * 65)

        for test_name, A, B in corner_cases(bits):

            expected = golden_result(A, B)

            actual, counts, ready = simulate_pe_array(A, B)

            for i in range(N):
                for j in range(N):

                    assert actual[i][j] == expected[i][j], (
                        f"FAIL: {test_name}, MODE {mode}, "
                        f"PE({i},{j})"
                    )

                    assert counts[i][j] == 16, "MAC count error"

                    assert ready[i][j] == i + j + 16, (
                        "Output clock error"
                    )

                    minimum = -(1 << (acc_width - 1))
                    maximum = (1 << (acc_width - 1)) - 1

                    assert minimum <= actual[i][j] <= maximum, (
                        "Accumulator overflow"
                    )

            if test_name == "Identity x Matrix":
                assert actual == B

            if test_name == "Matrix x Identity":
                assert actual == A

            print(
                f"PASS: {test_name:<22} "
                f"C[0][0]={actual[0][0]:>13} "
                f"C[15][15]={actual[15][15]:>13}"
            )

            total_tests += 1
            total_outputs += 256

    print("\n" + "=" * 65)
    print("ALL CORNER CASES PASSED")
    print(f"Total matrix tests: {total_tests}")
    print(f"Total PE output checks: {total_outputs}")
    print("Every PE completed 16 MAC operations")
    print("Output clock timing verified: 16 to 46")
    print("=" * 65)


verify_all()
