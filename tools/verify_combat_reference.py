"""Compile the recovered q.a(q) damage method with inert presentation stubs.

Cases intentionally exercise physical attacks without magic or equipment procs.
The original method, including its RNG call order, is the reference oracle.
"""
import argparse
import hashlib
import json
from pathlib import Path
from java_reference import method, run_reference

ROOT = Path(__file__).resolve().parent.parent


def generate(jdk):
    source = (ROOT / 'analysis/decompiled/q.java').read_text(encoding='utf-8')
    starters = json.loads((ROOT / 'tools/legacy_gameplay_reference.json').read_text())['starting_stats']
    hero, archer = starters['0'], starters['1']
    monster = [0] * 57
    for slot, value in {0: 20, 2: 6, 9: 15, 13: 10, 14: 20, 16: 6, 21: 42, 22: 37, 23: 20, 30: 598, 40: 1, 41: 1}.items():
        monster[slot] = value
    cases = []
    for index, (a, d, ranged, ap, protection, weapon) in enumerate([
        (hero, monster, False, 3, 1, 12), (hero, monster, False, 1, 5, 12),
        (archer, monster, True, 3, 1, 18), (monster, hero, False, 6, 1, -1),
        (hero, monster, False, 2, 1, 12), (archer, hero, True, 1, 5, 18),
    ]):
        a, d = a.copy(), d.copy()
        a[2] = ap
        d[21] *= protection
        cases.append(dict(seed=20261026 + index, attacker=a, defender=d, ranged=ranged, weapon=weapon, moved=0))
    blocked = dict(cases[0])
    blocked['defender'] = blocked['defender'].copy()
    blocked['defender'][41] = 101
    cases.append(blocked)
    java = '''import java.util.*;
public class CombatReference {
 static class aj {String[] e=new String[100],z=new String[10];aj(){Arrays.fill(e,"abcdefg");Arrays.fill(z,"x");}}
 static class v {v(int x,int y,String text){}}
 static class ac {ac(n a,int b,int x,int y){}}
 static class ab {int var_int_a;ab(int id){var_int_a=id;}}
 static class s {static int[][] var_int_arr_arr_e=new int[18][13];}
 static class m {
  Random random;
  Vector<ac> var_java_util_Vector_n=new Vector<ac>();
  int int_b(int bound){return Math.abs(random.nextInt()%bound);}
  void void_a(int a,int b,int c,int d,int e,int f){}
  void a(Object effect){}
 }
 static class n {
  int H,I,j=1,A,B,t,u,var_int_c;
  boolean var_boolean_d=false,var_boolean_i=false,var_boolean_c=false;
  q var_q_a,var_q_b;ab var_ab_a;
  void p(){} void j(){}
  int c(int delta){int previous=var_q_b.i[0];var_q_b.i[0]=Math.max(0,Math.min(var_q_b.i[14],previous+delta));return var_q_b.i[0]-previous;}
 }
 static class q {
  static m var_m_a=new m();n var_n_a;int[] i=new int[57];aj var_aj_a=new aj();
  q(n unit){var_n_a=unit;}
  void a(int slot,int value,int duration,int icon){}
  BLACK_METHOD
  WHITE_METHOD
  DAMAGE_METHOD
 }
 public static void main(String[] args)throws Exception {
  Scanner in=new Scanner(new java.io.File(args[0]));int cases=in.nextInt();
  for(int k=0;k<cases;k++) {
   long seed=in.nextLong();boolean ranged=in.nextInt()!=0;int weapon=in.nextInt(),moved=in.nextInt();
   n attacker=new n(),defender=new n();attacker.B=moved;
   attacker.var_q_b=new q(attacker);attacker.var_q_a=attacker.var_q_b;defender.var_q_b=new q(defender);defender.var_q_a=defender.var_q_b;
   if(weapon>=0)attacker.var_ab_a=new ab(weapon);
   for(int i=0;i<57;i++)attacker.var_q_b.i[i]=in.nextInt();for(int i=0;i<57;i++)defender.var_q_b.i[i]=in.nextInt();
   q payload=new q(attacker);payload.i[30]=attacker.var_q_b.i[30];payload.i[ranged?43:40]=1;
   q.var_m_a.random=new Random(seed);int before=defender.var_q_b.i[0];defender.var_q_b.a(payload);
   System.out.println(k+" "+(before-defender.var_q_b.i[0])+" "+q.var_m_a.random.nextInt());
  }
  Random random=new Random(20261026L);System.out.print("rng ");for(int i=0;i<12;i++)System.out.print(random.nextInt()+",");System.out.println();
 }
}'''
    for token, declaration in [('BLACK_METHOD', 'public final int int_b()'), ('WHITE_METHOD', 'public final int int_c()'), ('DAMAGE_METHOD', 'public final void a(q q2)')]:
        java = java.replace(token, method(source, declaration))
    build = ROOT / 'build/java-combat-reference'
    build.mkdir(parents=True, exist_ok=True)
    (build / 'CombatReference.java').write_text(java, encoding='utf-8')
    inputs = [str(len(cases))]
    for case in cases:
        inputs.append(' '.join(map(str, [case['seed'], int(case['ranged']), case['weapon'], case['moved'], *case['attacker'], *case['defender']])))
    (build / 'input.txt').write_text('\n'.join(inputs), encoding='utf-8')
    result = run_reference(jdk, build, 'CombatReference', 'input.txt')
    rng = []
    for line in result.splitlines():
        if line.startswith('rng '): rng = list(map(int, line[4:].rstrip(',').split(',')))
        else:
            index, damage, next_int = map(int, line.split())
            cases[index]['damage'] = damage
            cases[index]['next_int'] = next_int
    metadata = json.loads((ROOT / 'tools/legacy_gameplay.json').read_text(encoding='utf-8'))
    reference = {'source_sha256': metadata['source_sha256'], 'method_sha256': hashlib.sha256(method(source, 'public final void a(q q2)').encode('utf-8')).hexdigest(), 'coverage': 'ordinary physical attacks without magic or equipment procs', 'cases': cases, 'rng_seed': 20261026, 'rng': rng}
    (ROOT / 'tools/legacy_combat_reference.json').write_text(json.dumps(reference, indent=2) + '\n', encoding='utf-8')
    print(f'Java combat reference: {len(cases)} physical attacks + Random.nextInt stream')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--jdk', default='F:/apps/Java')
    generate(parser.parse_args().jdk)
