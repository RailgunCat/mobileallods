"""Generate arena goldens by compiling the actual m.s() bounds-growth prefix."""
import argparse
import hashlib
import json
from pathlib import Path

from java_reference import method, run_reference

ROOT = Path(__file__).resolve().parent.parent


def actor(identity, position, size=(1, 1), flag=0, party=False, triggered=False, state=0):
    return dict(id=identity, position=list(position), footprint=list(size), flag=flag, party=party, triggered=triggered, state=state)


def generate_reference(jdk):
    source = (ROOT / 'analysis/decompiled/m.java').read_text(encoding='utf-8')
    prefix = method(source, 'public final void s()').split('this.var_int_A =', 1)[0] + '\n}'
    cases = [
        {'name': 'demo', 'units': [actor(1, (344, 328), flag=1, party=True), actor(1002, (376, 328), flag=2, party=True), actor(1004, (352, 272), (2, 2), triggered=True), actor(1001, (344, 72), flag=5), actor(1000, (112, 480), (3, 3))]},
        {'name': 'chain-and-hidden', 'units': [actor(1, (328, 328), flag=1, party=True), actor(10, (352, 272), (2, 2), triggered=True), actor(11, (416, 304), (2, 2)), actor(12, (480, 304), (2, 2)), actor(13, (552, 304), (3, 3)), actor(14, (32, 32), flag=6, state=1)]},
        {'name': 'top-left-edge', 'units': [actor(1, (32, 48), flag=1, party=True), actor(10, (64, 80), (3, 3), triggered=True)]},
        {'name': 'bottom-right-edge', 'units': [actor(1, (584, 568), flag=1, party=True), actor(10, (552, 544), (2, 2), triggered=True)]},
    ]
    java = '''import java.util.*;
public class BattleReference {
 static class n {
  int id,H,I,j,k,t,u;byte var_byte_b;
  boolean var_boolean_b=false,var_boolean_d=false;
 }
 static class m {
  int Z,Y,ab,var_int_p,var_int_q,var_int_u,var_int_v,var_int_w,var_int_x,var_int_y,var_int_z,var_int_n,var_int_o;
  boolean var_boolean_d=false;
  n var_n_c,var_n_d;Object var_ah_a;
  byte[] var_byte_arr_d=new byte[50];
  Vector<n> var_java_util_Vector_f=new Vector<n>(),var_java_util_Vector_i=new Vector<n>(),var_java_util_Vector_j=new Vector<n>(),var_java_util_Vector_c=new Vector<n>(),var_java_util_Vector_b=new Vector<n>();
  void void_b(int value){}
  ARENA_METHOD
 }
 public static void main(String[] args)throws Exception {
  Scanner in=new Scanner(new java.io.File(args[0]));int count=in.nextInt();
  for(int c=0;c<count;c++) {
   m game=new m();game.var_int_n=in.nextInt();game.var_int_o=in.nextInt();game.var_int_p=in.nextInt();game.var_int_q=in.nextInt();
   int actors=in.nextInt();for(int i=0;i<actors;i++) {
    n a=new n();a.id=in.nextInt();a.H=in.nextInt();a.I=in.nextInt();a.j=in.nextInt();a.k=in.nextInt();a.t=(a.H-a.j*8)/16;a.u=(a.I-a.k*8)/16;
    a.var_byte_b=(byte)in.nextInt();game.var_byte_arr_d[a.var_byte_b]=(byte)in.nextInt();boolean party=in.nextInt()!=0;a.var_boolean_b=in.nextInt()!=0;
    game.var_java_util_Vector_b.add(a);if(party)game.var_java_util_Vector_j.add(a);else game.var_java_util_Vector_c.add(a);
   }
   game.s();System.out.print(c+" "+game.var_int_u+" "+game.var_int_v+" "+game.var_int_y+" "+game.var_int_z+" ");
   for(n a:game.var_java_util_Vector_j)System.out.print(a.id+",");
   for(n a:game.var_java_util_Vector_c)if(a.var_boolean_b&&!a.var_boolean_d&&game.var_byte_arr_d[a.var_byte_b]==0)System.out.print(a.id+",");
   System.out.println();
  }
 }
}'''.replace('ARENA_METHOD', prefix)
    build = ROOT / 'build/java-battle-reference'
    build.mkdir(parents=True, exist_ok=True)
    (build / 'BattleReference.java').write_text(java, encoding='utf-8')
    inputs = [str(len(cases))]
    for case in cases:
        hero = case['units'][0]
        case['width'] = case['height'] = 38
        inputs.append(f"38 38 {hero['position'][0] - 79} {hero['position'][1] - 95} {len(case['units'])}")
        for unit in case['units']:
            values = [unit['id'], *unit['position'], *unit['footprint'], unit['flag'], unit['state'], int(unit['party']), int(unit['triggered'])]
            inputs.append(' '.join(map(str, values)))
    (build / 'input.txt').write_text('\n'.join(inputs), encoding='utf-8')
    result = run_reference(jdk, build, 'BattleReference', 'input.txt')
    for line in result.splitlines():
        fields = line.split()
        case = cases[int(fields[0])]
        case['arena'] = list(map(int, fields[1:5]))
        case['participants'] = list(map(int, fields[5].rstrip(',').split(',')))
    path = ROOT / 'tools/legacy_battle_reference.json'
    metadata = json.loads((ROOT / 'tools/legacy_gameplay.json').read_text(encoding='utf-8'))
    path.write_text(json.dumps({'source_sha256': metadata['source_sha256'], 'source_method_sha256': hashlib.sha256(prefix.encode('utf-8')).hexdigest(), 'cases': cases}, indent=2) + '\n', encoding='utf-8')
    print(f'Java arena reference: {len(cases)} scenarios -> {path}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--jdk', default='F:/apps/Java')
    generate_reference(parser.parse_args().jdk)
