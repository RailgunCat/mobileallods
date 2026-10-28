"""Execute recovered item methods and equipped-stat aggregation with real tables."""
import argparse
import hashlib
import json
import re
from pathlib import Path
from java_reference import method, run_reference

ROOT = Path(__file__).resolve().parents[1]


def generate(jdk):
    sources = {name: (ROOT / f'analysis/decompiled/{name}.java').read_text(encoding='utf-8') for name in ['ab', 'q', 'm', 's']}
    prices = re.search(r'var_int_arr_f = new int\[\](\{.*?\});', sources['s'])[1]
    replacements = {
        'ITEM_CONSTRUCTOR': method(sources['ab'], 'public ab(int n2)'),
        'ITEM_PRICE': method(sources['ab'], 'public final int a()'),
        'ITEM_HERO': method(sources['ab'], 'public final int b()'),
        'AGGREGATE': method(sources['q'], 'public final void a(ab ab2, ab ab3)'),
        'DERIVED': method(sources['q'], 'public final void void_b()'),
        'SKILLS': method(sources['q'], 'public final void void_c()'),
        'REBUILD': method(sources['q'], 'public final q a(n n2, ab ab2, ab ab3)'),
        'SCALE': method(sources['m'], 'public final int int_d(int n2)'),
        'PRICES': prices,
    }
    java = '''import java.util.*;
public class EconomyReference {
 static class s {static int[] var_int_arr_f=new int[]PRICES;}
 static class ab {
  ab[] var_ab_arr_a;int var_int_a;byte var_byte_a,b;boolean var_boolean_a;
  ITEM_CONSTRUCTOR
  ITEM_PRICE
  ITEM_HERO
 }
 static class m {SCALE}
 static class n {q var_q_a,var_q_b;}
 static class q {
  static m var_m_a=new m();static int[][] table=new int[148][57];n var_n_a;int[] i=new int[57];
  Vector<int[]> var_java_util_Vector_a=new Vector<int[]>();
  q(n unit){var_n_a=unit;}int[] int_arr_a(int id){return table[id];}
  AGGREGATE
  DERIVED
  SKILLS
  REBUILD
 }
 public static void main(String[] args)throws Exception {
  Scanner in=new Scanner(new java.io.File(args[0]));for(int r=0;r<148;r++)for(int c=0;c<57;c++)q.table[r][c]=in.nextInt();
  System.out.print("{\\"items\\":[");boolean comma=false;
  for(int id=0;id<41;id++)for(int crystal=-1;crystal<5;crystal++) {
   ab item=new ab(id);if(crystal>=0)for(int i=0;i<item.b;i++)item.var_ab_arr_a[i]=new ab(36+crystal);
   if(comma)System.out.print(",");comma=true;
   System.out.print("{\\"definition_id\\":"+id+",\\"crystal\\":"+(crystal<0?-1:36+crystal)+",\\"kind\\":"+item.var_byte_a+",\\"hero_type\\":"+(id<36?item.b():-1)+",\\"sockets\\":"+item.b+",\\"price\\":"+item.a()+"}");
  }
  System.out.print("],\\"equipment\\":[");comma=false;
  for(int hero=0;hero<4;hero++)for(int grade=0;grade<6;grade++)for(int crystal=36;crystal<41;crystal++) {
   n actor=new n();actor.var_q_a=new q(actor);actor.var_q_b=new q(actor);actor.var_q_a.i=q.table[90+hero].clone();
   actor.var_q_a.i[9]+=2;actor.var_q_a.i[11]+=3;actor.var_q_a.i[13]+=1;
   ab weapon=new ab(12+hero*6+grade),armor=new ab(hero*3+grade%3);
   for(int i=0;i<weapon.b;i++)weapon.var_ab_arr_a[i]=new ab(crystal);
   for(int i=0;i<armor.b;i++)armor.var_ab_arr_a[i]=new ab(crystal);
   q effective=actor.var_q_a.a(actor,weapon,armor);
   if(comma)System.out.print(",");comma=true;
   System.out.print("{\\"type\\":"+hero+",\\"weapon\\":"+weapon.var_int_a+",\\"armor\\":"+armor.var_int_a+",\\"crystal\\":"+crystal+",\\"base\\":"+Arrays.toString(actor.var_q_a.i)+",\\"stats\\":"+Arrays.toString(effective.i)+"}");
  }
  System.out.println("]}");
 }
}
'''
    for key, value in replacements.items():
        java = java.replace(key, value)
    folder = ROOT / 'build/java-economy-reference'
    folder.mkdir(parents=True, exist_ok=True)
    (folder / 'EconomyReference.java').write_text(java, encoding='utf-8')
    table = json.loads((ROOT / 'analysis/extracted/tables/abilities.txt.json').read_text(encoding='utf-8'))
    (folder / 'input.txt').write_text('\n'.join(' '.join(map(str, row['values'] + [0])) for row in table['rows']), encoding='utf-8')
    output = run_reference(jdk, folder, 'EconomyReference', 'input.txt')
    reference = json.loads(output)
    reference['method_hashes'] = {key: hashlib.sha256(value.encode()).hexdigest() for key, value in replacements.items()}
    reference['source_sha256'] = json.loads((ROOT / 'tools/legacy_gameplay.json').read_text(encoding='utf-8'))['source_sha256']
    (ROOT / 'tools/legacy_economy_reference.json').write_text(json.dumps(reference, indent=2) + '\n', encoding='utf-8')
    print(f"Java economy reference: {len(reference['items'])} item cases, {len(reference['equipment'])} equipped-stat cases")


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--jdk', default='F:/apps/Java')
    generate(parser.parse_args().jdk)
