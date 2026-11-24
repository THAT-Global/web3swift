# Re-derives every vector in typed-data-vectors.json with an EIP-712 hasher that shares nothing with the package:
# pure Python, its own Keccak-256, written from the EIP's text.   python3 -I typed-data-vectors.py typed-data-vectors.json
import json, re, sys

RC = [0x0000000000000001, 0x0000000000008082, 0x800000000000808A, 0x8000000080008000, 0x000000000000808B, 0x0000000080000001,
      0x8000000080008081, 0x8000000000008009, 0x000000000000008A, 0x0000000000000088, 0x0000000080008009, 0x000000008000000A,
      0x000000008000808B, 0x800000000000008B, 0x8000000000008089, 0x8000000000008003, 0x8000000000008002, 0x8000000000000080,
      0x000000000000800A, 0x800000008000000A, 0x8000000080008081, 0x8000000000008080, 0x0000000080000001, 0x8000000080008008]
ROT = [[0, 36, 3, 41, 18], [1, 44, 10, 45, 2], [62, 6, 43, 15, 61], [28, 55, 25, 21, 56], [27, 20, 39, 8, 14]]
M = (1 << 64) - 1

def rol(x, n): return ((x << n) | (x >> (64 - n))) & M if n else x

def permute(A):
    for rc in RC:
        C = [A[x][0] ^ A[x][1] ^ A[x][2] ^ A[x][3] ^ A[x][4] for x in range(5)]
        D = [C[(x - 1) % 5] ^ rol(C[(x + 1) % 5], 1) for x in range(5)]
        A = [[A[x][y] ^ D[x] for y in range(5)] for x in range(5)]
        B = [[0] * 5 for _ in range(5)]
        for x in range(5):
            for y in range(5): B[y][(2 * x + 3 * y) % 5] = rol(A[x][y], ROT[x][y])
        A = [[B[x][y] ^ ((~B[(x + 1) % 5][y]) & B[(x + 2) % 5][y]) for y in range(5)] for x in range(5)]
        A[0][0] ^= rc
    return A

def keccak(data):
    rate = 136; p = bytearray(data); p.append(0x01)
    while len(p) % rate: p.append(0)
    p[-1] |= 0x80
    A = [[0] * 5 for _ in range(5)]
    for off in range(0, len(p), rate):
        for i in range(rate // 8): A[i % 5][i // 5] ^= int.from_bytes(p[off + 8 * i:off + 8 * i + 8], 'little')
        A = permute(A)
    return b''.join(A[i % 5][i // 5].to_bytes(8, 'little') for i in range(4))

assert keccak(b'').hex() == 'c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470'

STANDARD = [("name", "string"), ("version", "string"), ("chainId", "uint256"), ("verifyingContract", "address"), ("salt", "bytes32")]

def hashes(d):
    T = dict(d['types'])
    # A domain type the JSON leaves out is the standard fields its domain carries, in the EIP's order.
    T.setdefault('EIP712Domain', [{"name": n, "type": t} for n, t in STANDARD if n in d['domain']])
    def deps(t, acc):
        t = re.sub(r'\[.*$', '', t)
        if t in T and t not in acc:
            acc.add(t)
            for field in T[t]: deps(field['type'], acc)
        return acc
    def enc_type(t):
        return ''.join(n + '(' + ','.join(f"{x['type']} {x['name']}" for x in T[n]) + ')' for n in [t] + sorted(deps(t, set()) - {t}))
    def num(v): return int(v, 16) if isinstance(v, str) and v[:2] in ('0x', '0X') else int(v)
    def enc_val(t, v):
        m = re.match(r'^(.*)\[(\d*)\]$', t)
        if m: return keccak(b''.join(enc_val(m.group(1), x) for x in v))
        if t in T: return hash_struct(t, v)
        if t == 'string': return keccak(v.encode())
        if t == 'bytes': return keccak(bytes.fromhex(v[2:]))
        if t == 'bool': return int(bool(v)).to_bytes(32, 'big')
        if t == 'address': return bytes.fromhex(v[2:]).rjust(32, b'\0')
        if t.startswith('uint'): return num(v).to_bytes(32, 'big')
        if t.startswith('int'): return (num(v) % (1 << 256)).to_bytes(32, 'big')
        if t.startswith('bytes'): return bytes.fromhex(v[2:]).ljust(32, b'\0')
        raise SystemExit('type ' + t)
    def hash_struct(t, v): return keccak(keccak(enc_type(t).encode()) + b''.join(enc_val(x['type'], v[x['name']]) for x in T[t]))
    domain = hash_struct('EIP712Domain', d['domain']); message = hash_struct(d['primaryType'], d['message'])
    return domain.hex(), message.hex(), keccak(b'\x19\x01' + domain + message).hex()

bad = 0
for vector in json.load(open(sys.argv[1]))['vectors']:
    ok = hashes(json.loads(vector['typedData'])) == (vector['domainHash'], vector['messageHash'], vector['digest'])
    bad += not ok
    print('ok  ' if ok else 'BAD ', vector['name'])
sys.exit(1 if bad else 0)
