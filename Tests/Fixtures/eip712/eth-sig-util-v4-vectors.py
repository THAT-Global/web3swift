# Re-derives eth-sig-util-v4-vectors.json with nothing from the package: pure Python, its own Keccak-256, EIP-712 and
# secp256k1 (RFC 6979 nonces, low s).
#   python3 -I eth-sig-util-v4-vectors.py eth-sig-util-v4-vectors.json [typed-data-vectors.json]   checks; exit 1 on any BAD
#   python3 -I eth-sig-util-v4-vectors.py --write eth-sig-util-v4-vectors.json                        adds "v4", "why", "digest"
#
# Two readers, written apart:
# - `phone`: the phone-key reading (EIP712Document.Reading.signTypedDataV4). For a case it reads, the hashes and the
#   signature must be eth-sig-util's. A case it refuses carries the reason as "why". An encodeType case is answered from
#   the types alone, as eth-sig-util answers it (a struct name the types do not define is left out).
# - `metamask`: eth-sig-util V4's own lenient encoder, emulated (sign-typed-data.ts at the fixture's commit). It must give
#   eth-sig-util's recorded value for every case, read or refused: proof that this file reads eth-sig-util as it is, and
#   that every refusal is of something eth-sig-util signs (or throws on).
# With a second argument, the 29 vectors of typed-data-vectors.json are read the phone-key way too: each must give its
# recorded hashes, except a document that leaves its domain type out, which the phone-key reading refuses.
import hashlib, hmac, json, re, sys

# Keccak-256 (the same construction as typed-data-vectors.py)
RC = [0x0000000000000001, 0x0000000000008082, 0x800000000000808A, 0x8000000080008000, 0x000000000000808B, 0x0000000080000001,
      0x8000000080008081, 0x8000000000008009, 0x000000000000008A, 0x0000000000000088, 0x0000000080008009, 0x000000008000000A,
      0x000000008000808B, 0x800000000000008B, 0x8000000000008089, 0x8000000000008003, 0x8000000000008002, 0x8000000000000080,
      0x000000000000800A, 0x800000008000000A, 0x8000000080008081, 0x8000000000008080, 0x0000000080000001, 0x8000000080008008]
ROT = [[0, 36, 3, 41, 18], [1, 44, 10, 45, 2], [62, 6, 43, 15, 61], [28, 55, 25, 21, 56], [27, 20, 39, 8, 14]]
M64 = (1 << 64) - 1
def rol(x, n): return ((x << n) | (x >> (64 - n))) & M64 if n else x
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

# secp256k1
P = 2 ** 256 - 2 ** 32 - 977
N = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141
G = (0x79BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798, 0x483ADA7726A3C4655DA4FBFC0E1108A8FD17B448A68554199C47D08FFB10D4B8)
def add(a, b):
    if a is None: return b
    if b is None: return a
    if a[0] == b[0] and (a[1] + b[1]) % P == 0: return None
    lam = (3 * a[0] * a[0] * pow(2 * a[1], -1, P)) % P if a == b else ((b[1] - a[1]) * pow(b[0] - a[0], -1, P)) % P
    x = (lam * lam - a[0] - b[0]) % P
    return (x, (lam * (a[0] - x) - a[1]) % P)
def mul(k, pt=G):
    out = None
    while k:
        if k & 1: out = add(out, pt)
        pt = add(pt, pt); k >>= 1
    return out
def address(key):
    pub = mul(int.from_bytes(key, 'big'))
    return keccak(pub[0].to_bytes(32, 'big') + pub[1].to_bytes(32, 'big'))[12:]
def sign(digest, key):
    x = int.from_bytes(key, 'big'); z = int.from_bytes(digest, 'big')
    mac = lambda k, m: hmac.new(k, m, hashlib.sha256).digest()
    V, K = b'\x01' * 32, b'\x00' * 32
    seed = key + (z % N).to_bytes(32, 'big')
    K = mac(K, V + b'\x00' + seed); V = mac(K, V)
    K = mac(K, V + b'\x01' + seed); V = mac(K, V)
    while True:
        V = mac(K, V); k = int.from_bytes(V, 'big')
        if 1 <= k < N:
            R = mul(k); r = R[0] % N; s = pow(k, -1, N) * (z + r * x) % N
            if r and s:
                rec = (R[1] & 1) | (2 if R[0] >= N else 0)
                if s > N // 2: s, rec = N - s, rec ^ 1
                return r.to_bytes(32, 'big') + s.to_bytes(32, 'big') + bytes([27 + rec])
        K = mac(K, V + b'\x00'); V = mac(K, V)

# JSON, keeping each number's text and refusing a repeated key
class Num:
    def __init__(self, text): self.text = text
    def __repr__(self): return self.text
class Dup(Exception): pass
def pairs(items):
    out = {}
    for k, v in items:
        if k in out: raise Dup(k)
        out[k] = v
    return out
def load(text): return json.loads(text, parse_int=Num, parse_float=Num, parse_constant=lambda c: (_ for _ in ()).throw(ValueError(c)), object_pairs_hook=pairs)

class Refused(Exception): pass

# Types as EIP-712 writes them (the canonical spelling only)
def primitive(t):
    if t in ('address', 'bool', 'string', 'bytes'): return (t, None)
    m = re.fullmatch(r'(u?int|bytes)([1-9][0-9]{0,2})', t)
    if not m: return None
    kind, n = m.group(1), int(m.group(2))
    if kind == 'bytes': return ('bytes', n) if n <= 32 else None
    return (kind, n) if n <= 256 and n % 8 == 0 else None
def parse_type(t):
    """('prim', p) | ('struct', name) | ('array', element text, count or None)."""
    p = primitive(t)
    if p: return ('prim', p)
    if re.fullmatch(r'[^\[\]]*(\[(0|[1-9][0-9]*)?\])+', t, re.S):
        i = t.rindex('[')  # the last bracket is the outermost dimension
        return ('array', t[:i], int(t[i + 1:-1]) if t[i + 1:-1] else None)
    return ('struct', t)
def root(t):
    k = parse_type(t)
    while k[0] == 'array': k = parse_type(k[1])
    return k

OBJECT_PROTOTYPE = {'constructor', 'hasOwnProperty', 'isPrototypeOf', 'propertyIsEnumerable', 'toLocaleString', 'toString',
                    'valueOf', '__defineGetter__', '__defineSetter__', '__lookupGetter__', '__lookupSetter__', '__proto__'}
SAFE = 2 ** 53 - 1
# What both the old web3swift (.whitespacesAndNewlines) and JavaScript's BigInt trim from a number string: the 24 scalars
# EIP712Reader.trimmedOfSpace trims. JavaScript's BigInt trims these and U+FEFF (JS_SPACE, for the emulation below).
SPACE = '\t\n\x0b\x0c\r\u2028\u2029' + ''.join(chr(c) for c in [0x20, 0xA0, 0x1680, *range(0x2000, 0x200B), 0x202F, 0x205F, 0x3000])
JS_SPACE = SPACE + '\ufeff'
assert len(SPACE) == 24

def exact_double_integer(text):
    """A JSON number's value when it is a whole number an IEEE-754 double holds exactly; else Refused."""
    m = re.fullmatch(r'(-?)([0-9]+)(?:\.([0-9]+))?(?:[eE]([+-]?[0-9]+))?', text)
    if not m: raise Refused('a number that is not a number')
    digits = (m.group(2) + (m.group(3) or '')).lstrip('0')
    scale = int(m.group(4) or 0) - len(m.group(3) or '')
    if not digits: return 0
    stripped = digits.rstrip('0'); scale += len(digits) - len(stripped)
    if scale < 0: raise Refused('a JSON number that is not a whole number')
    if len(stripped) + scale > 309: raise Refused('a JSON number past what a double holds')
    n = int(stripped) * 10 ** scale
    odd = n
    while odd % 2 == 0: odd //= 2
    if n >= 2 ** 1024 or odd >= 2 ** 53: raise Refused('a JSON number JavaScript cannot hold exactly')
    return -n if m.group(1) else n

def read_types(d):
    """The phone-key reading's struct definitions: {name: [(field, type)]}, or Refused."""
    T = {}
    for name, fields in d['types'].items():
        if not isinstance(fields, list): raise Refused('a type that is not a list of fields')
        seen = set()
        for f in fields:
            if not isinstance(f, dict) or not isinstance(f.get('name'), str) or not isinstance(f.get('type'), str):
                raise Refused('a field without a name and a type')
            if f['name'] in seen: raise Refused('a field twice')
            seen.add(f['name'])
        if not re.fullmatch(r'[A-Za-z0-9_]+', name): raise Refused('a type name outside [A-Za-z0-9_]')
        if primitive(name): raise Refused('a type named as an atomic type')
        if name in OBJECT_PROTOTYPE: raise Refused('a type named as a member every JavaScript object has')
        T[name] = [(f['name'], f['type']) for f in fields]
    return T

def encode_type(T, name):
    """EIP-712's encodeType; a struct name T does not define is left out, as eth-sig-util leaves it out."""
    deps, todo = set(), [name]
    while todo:
        n = todo.pop()
        if n in deps or n not in T: continue
        deps.add(n)
        for _, t in T[n]:
            k = root(t)
            if k[0] == 'struct': todo.append(k[1])
    order = [name] + sorted(deps - {name})
    return ''.join(n + '(' + ','.join('%s %s' % (t, f) for f, t in T[n]) + ')' for n in order)

def phone_encode_type(text, name):
    try:
        d = load(text)
    except (Dup, ValueError):
        raise Refused('not JSON')
    T = read_types(d)
    if name not in T: raise Refused('the type is not defined')
    return encode_type(T, name)

def phone(text):
    """The phone-key reading: (types, domain hash, message hash, digest, encodeType) or Refused(why)."""
    try:
        d = load(text)
    except Dup as e:
        raise Refused('a repeated key')
    except ValueError:
        raise Refused('not JSON')
    if not isinstance(d, dict) or not isinstance(d.get('types'), dict) or not isinstance(d.get('primaryType'), str) \
            or not isinstance(d.get('domain'), dict) or not isinstance(d.get('message'), dict):
        raise Refused('needs types, primaryType, domain and message')
    T = read_types(d)
    if 'EIP712Domain' not in T: raise Refused('no EIP712Domain type')
    primary = d['primaryType']
    if primary not in T: raise Refused('the primary type is not defined')
    if primary == 'EIP712Domain': raise Refused('the domain as the primary type')
    def struct_root(t):
        k = root(t)
        return k[1] if k[0] == 'struct' else None
    if any(struct_root(t) for _, t in T['EIP712Domain']): raise Refused('a domain field of a struct type')
    # Every struct a reached type names is defined, whether or not a value reaches it (an empty array never does).
    reached, todo = set(), [primary, 'EIP712Domain']
    while todo:
        n = todo.pop()
        if n in reached: continue
        if n not in T: raise Refused('an undefined type')
        reached.add(n)
        todo += [struct_root(t) for _, t in T[n] if struct_root(t)]
    enc_type = lambda name: encode_type(T, name)

    def integer(v, signed, bits):
        if isinstance(v, Num):
            n = exact_double_integer(v.text)
        elif isinstance(v, str):
            s = v.strip(SPACE)
            if re.fullmatch(r'0x[0-9a-fA-F]+', s): n = int(s, 16)
            elif re.fullmatch(r'[-+]?[0-9]+', s): n = int(s)
            else: raise Refused('a number written neither in decimal nor as 0x hex')
        else: raise Refused('a number that is not a number')
        lo, hi = (-(1 << (bits - 1)), (1 << (bits - 1)) - 1) if signed else (0, (1 << bits) - 1)
        if not lo <= n <= hi: raise Refused("a number out of its type's range")
        return (n % (1 << 256)).to_bytes(32, 'big')
    def hexbytes(v, size, address=False):
        if not isinstance(v, str) or not re.fullmatch(r'0x[0-9a-fA-F]*', v): raise Refused('bytes that are not 0x hex')
        h = v[2:]
        if len(h) % 2:
            if address: raise Refused('bytes that are not 0x hex of whole bytes')
            h = '0' + h  # eth-sig-util's hexToBytes
        b = bytes.fromhex(h)
        if size is None: return b
        if len(b) > size or (address and len(b) != size): raise Refused('bytes of the wrong length')
        return b.ljust(size, b'\0')
    def prim(p, v):
        kind, n = p
        if kind == 'string':
            if not isinstance(v, str): raise Refused('a string that is not text')
            return keccak(v.encode('utf-8'))
        if kind == 'bytes' and n is None: return keccak(hexbytes(v, None))
        if kind == 'bytes':
            if isinstance(v, Num):
                x = exact_double_integer(v.text)
                if x not in (0, 1): raise Refused('a number in place of bytes, other than 0 or 1')
                return bytes([x]).ljust(32, b'\0')
            return hexbytes(v, n).ljust(32, b'\0')
        if kind == 'address': return hexbytes(v, 20, address=True).rjust(32, b'\0')
        if kind == 'bool':
            if v is True or v is False: return int(v).to_bytes(32, 'big')
            raise Refused('a bool that is not true or false')
        return integer(v, kind == 'int', n)
    def value(t, v, depth, field_absent=False, field_name=None):
        if depth > 32: raise Refused('nested too deep')
        k = parse_type(t)
        if k[0] == 'struct':
            if k[1] not in T: raise Refused('an undefined type')
            if field_absent:
                if field_name in OBJECT_PROTOTYPE: raise Refused('a struct left out under a name JavaScript objects inherit')
                return b'\0' * 32
            if v is None: return b'\0' * 32
            return hash_struct(k[1], v, depth)
        if field_absent: raise Refused('a field left out')
        if k[0] == 'array':
            if not isinstance(v, list): raise Refused('an array that is not a list')
            if k[2] is not None and k[2] != len(v): raise Refused('a fixed array of another length')
            return keccak(b''.join(value(k[1], x, depth + 1) for x in v))
        if v is None: raise Refused('null where a value is due')
        return prim(k[1], v)
    def hash_struct(name, v, depth):
        if not isinstance(v, dict): raise Refused('a struct that is not an object')
        enc = keccak(enc_type(name).encode('utf-8'))
        for f, t in T[name]:
            enc += value(t, v.get(f), depth + 1, field_absent=f not in v, field_name=f)
        return keccak(enc)
    dh = hash_struct('EIP712Domain', d['domain'], 0)
    mh = hash_struct(primary, d['message'], 0)
    return T, dh, mh, keccak(b'\x19\x01' + dh + mh), enc_type

def isnum(v): return isinstance(v, (int, float)) and not isinstance(v, bool)

def metamask(text, only_type=False):
    """eth-sig-util V4 (sign-typed-data.ts), emulated: its digest and encodeType, or an exception where it throws."""
    # A JSON number is a double in JavaScript: past 2^53 it is the nearest one.
    d = json.loads(text, parse_int=lambda s: int(float(s)) if abs(int(s)) > SAFE else int(s), parse_float=float)
    def truthy(v): return v is not None and v is not False and v != '' and not (isnum(v) and v == 0)
    data = {k: d[k] for k in ('types', 'primaryType', 'domain', 'message') if k in d and truthy(d[k])}  # sanitizeData
    types = dict({'EIP712Domain': []}, **data['types']) if 'types' in data else None
    def to_bytes_num(n):  # numberToBytes (a safe integer) / bigIntToBytes
        if isinstance(n, float):
            if n != int(n) or abs(n) > SAFE: raise ValueError('not a safe integer')
            n = int(n)
        h = '%x' % n
        return bytes.fromhex(('0' + h) if len(h) % 2 else h)
    def hex_to_bytes(s):
        h = s[2:]
        return bytes.fromhex(('0' + h) if len(h) % 2 else h)
    def strict_hex(v): return isinstance(v, str) and re.fullmatch(r'0x[0-9a-fA-F]+', v) is not None
    def big(v):
        if isinstance(v, bool) or v is None: raise ValueError('not a number')
        if isinstance(v, int): return v
        if isinstance(v, float):
            if v != int(v): raise ValueError('fraction')
            return int(v)
        s = v.strip(JS_SPACE)
        if s == '': return 0
        if re.fullmatch(r'0[xX][0-9a-fA-F]+', s): return int(s, 16)
        if re.fullmatch(r'[+-]?[0-9]+', s): return int(s)
        raise ValueError('not a number: %r' % v)
    def length(t):
        m = re.search(r'(\d+)$', t)
        return int(m.group(1)) if m else 256
    def word_uint(n, bits):
        if not 0 <= n <= (1 << bits) - 1: raise ValueError('out of range')
        return n.to_bytes(32, 'big')
    def strange(a):
        value = 0
        for ch in a:
            c = ord(ch) - 48
            value *= 10
            value += c - 49 + 10 if c >= 49 else c - 17 + 10 if c >= 17 else c
        b = to_bytes_num(value).rjust(20, b'\0')
        return b[:20]
    def field(types, name, t, v, present):
        if t in types:
            if v is None: return b'\0' * 32
            return keccak(encode_data(t, v, types))
        if t == 'function': raise ValueError('function')
        if not present: raise ValueError('missing value for field %s of type %s' % (name, t))
        if t == 'address':
            if isnum(v): b = to_bytes_num(v).rjust(20, b'\0')
            elif strict_hex(v): b = hex_to_bytes(v)
            elif isinstance(v, str): b = strange(v)
            else: raise ValueError('address')
            if len(b) > 20: raise ValueError('address of %d bytes' % len(b))
            return b.rjust(32, b'\0')
        if t == 'bool':
            if v is True or v == 'true': return (1).to_bytes(32, 'big')
            if v is False or v == 'false': return (0).to_bytes(32, 'big')
            raise ValueError('bool')
        if t == 'bytes':
            if isnum(v): b = to_bytes_num(v)
            elif strict_hex(v) or v == '0x': b = hex_to_bytes(v)
            elif isinstance(v, str): b = v.encode('utf-8')
            else: raise ValueError('bytes')
            return keccak(b)
        if t.startswith('bytes') and '[' not in t:
            if isnum(v): b = b'' if v < 0 else to_bytes_num(v)
            elif strict_hex(v) or v == '0x': b = hex_to_bytes(v)
            else: raise ValueError('Expected a bytes-like value')
            if len(b) > 32: raise ValueError('too long')
            return b.ljust(32, b'\0')
        if t.startswith('int') and '[' not in t:
            n = big(v); mx = (1 << length(t)) - 1
            if not -mx <= n <= mx: raise ValueError('out of range')
            return (n % (1 << 256)).to_bytes(32, 'big')
        if t == 'string':
            if isnum(v): b = to_bytes_num(v)
            else: b = ('' if v is None else v).encode('utf-8')
            return keccak(b)
        if t.endswith(']'):
            inner = t[:t.rindex('[')]
            return keccak(b''.join(field(types, name, inner, x, True) for x in v))
        if re.fullmatch(r'uint\d*', t):
            if isinstance(v, bool) or v is None: raise ValueError('uint')
            n = big(v)
            if n < 0: raise ValueError('Value must be a non-negative bigint.')
            return word_uint(n, length(t))
        raise ValueError('The type "%s" is not supported.' % t)
    def deps(t, types, acc):
        t = re.match(r'^\w*', t).group(0)
        if t in acc or t not in types: return acc
        acc.add(t)
        for f in types[t]: deps(f['type'], types, acc)
        return acc
    def encode_type(t, types):
        ds = deps(t, types, set()); ds.discard(t)
        out = ''
        for n in [t] + sorted(ds):
            if n not in types: raise ValueError('No type definition specified: ' + n)
            out += n + '(' + ','.join('%s %s' % (f['type'], f['name']) for f in types[n]) + ')'
        return out
    def encode_data(t, v, types):
        enc = keccak(encode_type(t, types).encode('utf-8'))
        for f in types[t]:
            present = isinstance(v, dict) and f['name'] in v
            enc += field(types, f['name'], f['type'], v.get(f['name']) if isinstance(v, dict) else None, present)
        return enc
    if only_type: return None, None, lambda name: encode_type(name, types)
    dh = keccak(encode_data('EIP712Domain', data.get('domain'), {'EIP712Domain': types['EIP712Domain']}))
    parts = b'\x19\x01' + dh
    mh = None
    if data.get('primaryType') != 'EIP712Domain':
        mh = keccak(encode_data(data['primaryType'], data.get('message'), types))
        parts += mh
    return mh, keccak(parts), lambda name: encode_type(name, types)

def check(path, write):
    f = json.load(open(path, encoding='utf-8'))
    key = bytes.fromhex(f['source']['privateKey'].split(': ')[-1])
    bad = 0
    for c in f['cases']:
        want = c['ethSigUtil']
        # eth-sig-util, emulated, gives its recorded value.
        try:
            mh, digest, enc = metamask(c['typedData'], only_type='encodeType' in want)
            if 'hashStruct' in want: got = mh.hex() == want['hashStruct']
            elif 'eip712Hash' in want: got = digest.hex() == want['eip712Hash']
            elif 'signature' in want: got = '0x' + sign(digest, key).hex() == want['signature']
            elif 'encodeType' in want: got = enc(c['encodeTypeOf']) == want['encodeType']
            else: got = False
        except Exception:
            got = 'throws' in want
        if not got:
            bad += 1; print('BAD metamask', c['name'])
        # The phone-key reading: eth-sig-util's value, or a refusal.
        try:
            if 'encodeType' in want or (c['check'] == 'encodeType'):
                text = phone_encode_type(c['typedData'], c['encodeTypeOf'])
                if 'throws' in want: ok = False
                else: ok = text == want['encodeType']
                verdict, why, derived = 'same', None, None
                raise StopIteration
            T, dh, mh, digest, enc = phone(c['typedData'])
            verdict, why = 'same', None
            if 'throws' in want: ok = False
            elif 'hashStruct' in want: ok = mh.hex() == want['hashStruct']
            elif 'eip712Hash' in want: ok = digest.hex() == want['eip712Hash']
            elif 'signature' in want: ok = '0x' + sign(digest, key).hex() == want['signature']
            elif 'encodeType' in want: ok = enc(c['encodeTypeOf']) == want['encodeType']
            derived = digest.hex()
        except StopIteration:
            pass
        except Refused as e:
            verdict, why, ok, derived = 'refused', str(e), True, None
        if write:
            c['v4'] = verdict
            c.pop('why', None); c.pop('digest', None)
            if why: c['why'] = why
            if derived and 'signature' in want: c['digest'] = derived
        elif c.get('v4') != verdict or c.get('why') != why or ('signature' in want and c.get('digest') != derived):
            ok = False
        if not ok:
            bad += 1; print('BAD phone', c['name'], verdict, why)
        else:
            print('ok  ', verdict.ljust(7), c['name'], '' if why is None else '-- ' + why)
    if write:
        json.dump(f, open(path, 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
        open(path, 'a').write('\n')
    print(sum(c.get('v4') == 'same' for c in f['cases']), 'read,', sum(c.get('v4') == 'refused' for c in f['cases']), 'refused')
    return bad

def check_vectors(path):
    bad = 0
    for v in json.load(open(path, encoding='utf-8'))['vectors']:
        try:
            _, dh, mh, digest, _ = phone(v['typedData'])
            ok = (dh.hex(), mh.hex(), digest.hex()) == (v['domainHash'], v['messageHash'], v['digest'])
            print('ok  ' if ok else 'BAD ', 'same   ', v['name'])
        except Refused as e:
            ok = 'EIP712Domain' not in load(v['typedData'])['types']
            print('ok  ' if ok else 'BAD ', 'refused', v['name'], '--', e)
        bad += not ok
    return bad

if __name__ == '__main__':
    args = sys.argv[1:]
    write = args[:1] == ['--write']
    if write: args = args[1:]
    bad = check(args[0], write)
    if len(args) > 1: bad += check_vectors(args[1])
    sys.exit(1 if bad else 0)
