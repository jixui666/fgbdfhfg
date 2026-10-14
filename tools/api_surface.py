import sys, struct, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from macho_parse import MachO

FW = 'Frameworks/libuiopsersvc.framework/libuiopsersvc'
if not os.path.exists(FW):
    FW = 'vendor/libuiopsersvc.framework/libuiopsersvc'

fw = MachO(FW)
exp = set(fw.exports())
print('framework exports: %d' % len(exp))

op = MachO('OPEN')
und = [nm for nm, t, s, v in op.symbols() if (t & 0x0E) == 0 and (t & 0x80) == 0]
unds = set(und)
print('OPEN undefined symbols: %d' % len(unds))

api = sorted(unds & exp)
print('\nOPEN-imported-from-libuiopsersvc (%d):' % len(api))
for s in api:
    print('  _%s' % s)

# also symbols OPEN imports that framework may define via re-export chains (grabkernel2, xpf, ATHelper)
print('\nAny framework export NOT used by OPEN: %d' % len(exp - unds))

# framework objc classnames
cn = [s for _, s in fw.strings_in_sec('__TEXT', '__objc_classname')]
print('\nframework ObjC classes:')
for c in cn:
    print('  ' + c)
