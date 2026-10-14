import sys, struct, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from macho_parse import MachO, uleb

def dump_open(path, out):
    m = MachO(path)
    w = out.write
    w('FILE: %s thin=%s len=%d\n' % (path, m.fat, len(m.data)))
    w('ncmds=%d uuid=%s cryptid=%s\n' % (m.ncmds, m.uuid, m.cryptid))
    w('SEGMENTS:\n')
    for s in m.segments:
        w('  %-14s vm=0x%011X size=0x%X foff=0x%X fsize=0x%X\n' % (s['name'], s['vmaddr'], s['vmsize'], s['fileoff'], s['filesize']))
    w('DYLIB LOAD CMDS:\n')
    for k, p in m.dylibs:
        w('  %-22s %s\n' % (k, p))
    syms = m.symbols()
    if syms:
        w('SYMBOLS: %d\n' % len(syms))
        und = [s for s in syms if (s[1] & 0x0E) == 0 and s[1] & 0x80 == 0]
        # n_desc high byte = ordinal (for undefined two-level)
        w('UNDEFINED (%d):\n' % len(und))
        for nm, t, v in und:
            w('  %s\n' % nm)
        w('DEFINED (%d):\n' % (len(syms) - len(und)))
        for nm, t, v in syms:
            if not ((t & 0x0E) == 0 and (t & 0x80) == 0):
                w('  0x%X t=0x%02X %s\n' % (v, t, nm))
    # strings of interest
    cstr = m.strings_in_sec('__TEXT', '__cstring', minlen=3)
    kw = ('wallet', 'Wallet', 'keychain', 'Keychain', 'collect', 'container', 'Container',
          'libuiopser', 'meta', 'Meta', 'trust', 'Trust', 'imtoken', 'ImToken', 'coin98', 'Coin98',
          'bitpie', 'Bitpie', 'okx', 'OKX', 'phantom', 'Phantom', 'tokenpocket', 'TokenPocket',
          'electrum', 'exodus', 'uni', 'trustwallet', 'atomic', 'binance', 'safepal', 'onekey',
          'celo', 'crypto', 'walletconnect', 'xumm', 'zeus', 'bluewallet')
    w('\nINTERESTING STRINGS:\n')
    for off, s in cstr:
        if any(k in s for k in kw):
            w('  +0x%X %s\n' % (off, s))
    # all cstring count
    w('\ncstring count: %d\n' % len(cstr))

out = open('macho_open_report.txt', 'w', encoding='utf-8')
try:
    dump_open('OPEN', out)
except Exception as e:
    import traceback
    out.write('ERROR: %r\n' % e)
    traceback.print_exc(file=out)
out.close()
print('done')
