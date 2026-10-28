"""Compile actual recovered q methods for spell payloads, effects and damage.

Rendering is inert. Stat aggregation, effect replacement/expiration, RNG and
all damage branches execute the original Java method bodies.
"""
import argparse
import hashlib
import json
import shutil
from pathlib import Path
from java_reference import method, run_reference

ROOT = Path(__file__).resolve().parents[1]


def generate(jdk):
    q_source = (ROOT / 'analysis/decompiled/q.java').read_text(encoding='utf-8')
    m_source = (ROOT / 'analysis/decompiled/m.java').read_text(encoding='utf-8')
    n_source = (ROOT / 'analysis/decompiled/n.java').read_text(encoding='utf-8')
    o_source = (ROOT / 'analysis/decompiled/o.java').read_text(encoding='utf-8')
    metadata = json.loads((ROOT / 'tools/legacy_gameplay.json').read_text(encoding='utf-8'))
    table = json.loads((ROOT / 'analysis/extracted/tables/abilities.txt.json').read_text(encoding='utf-8'))
    java = '''import java.util.*;import java.io.*;
public class MagicReference {
 TRIG_CLASS
 static class aa {boolean var_boolean_a=false;int[] point;aa(n a,int x,int y,int delay){point=new int[]{x,y};}}
 static class aj {String[] e=new String[100],z=new String[20];aj(){Arrays.fill(e,"abcdefghi");Arrays.fill(z,"x");}}
 static class v {v(int x,int y,String text){}}
 static class ac {ac(n a,int b,int x,int y){}}
 static class ab {int var_int_a,b;ab[] var_ab_arr_a=new ab[10];ab(int id){var_int_a=id;}int b(){return (var_int_a-12)/6;}}
 static class s {static int[][] var_int_arr_arr_e=new int[18][13];static int[][] var_int_arr_arr_a=ACTION_TABLE;}
 static class m {
  Random random=new Random(1);Vector<ac> var_java_util_Vector_n=new Vector<ac>();Vector<aa> var_java_util_Vector_g=new Vector<aa>();o var_o_a=new o();
  int int_b(int bound){return Math.abs(random.nextInt()%bound);}
  void void_a(int a,int b,int c,int d,int e,int f){} void a(Object effect){}
  SCALE_METHOD
  COST_METHOD
  ROOT_METHOD
 }
 static class n {
  static m var_m_a=q.var_m_a;
  int H,I,j=1,A,B,t,u,var_int_c;boolean var_boolean_d=false,var_boolean_i=false,var_boolean_c=false;
  q var_q_a,var_q_b;ab var_ab_a,var_ab_b;
  void p(){var_q_b=var_q_a.a(this,var_ab_a,var_ab_b);} void j(){}
  int c(int delta){int before=var_q_b.i[0];var_q_b.i[0]=Math.max(0,Math.min(var_q_b.i[14],before+delta));return var_q_b.i[0]-before;}
  WALL_METHOD
 }
 static class q {
  static m var_m_a=new m();static int[][] table=new int[148][57];n var_n_a;int[] i=new int[57];
  Vector<int[]> var_java_util_Vector_a=new Vector<int[]>();aj var_aj_a=new aj();
  q(n unit){var_n_a=unit;}int[] int_arr_a(int id){return table[id];}
  AGGREGATE_METHOD
  DERIVED_METHOD
  SKILL_METHOD
  REBUILD_METHOD
  ADD_METHOD
  TICK_METHOD
  BLACK_METHOD
  WHITE_METHOD
  PAYLOAD_METHOD
  DAMAGE_METHOD
 }
 static n unit(int type){
  n a=new n();a.var_int_c=type;a.var_q_a=new q(a);a.var_q_a.i=q.table[90+type].clone();a.var_q_b=new q(a);
  if(type<4){a.var_ab_a=new ab(12+type*6);a.var_ab_b=new ab(type*3);}a.p();
  a.var_q_b.i[0]=a.var_q_b.i[14];a.var_q_b.i[1]=a.var_q_b.i[15];a.var_q_b.i[2]=a.var_q_b.i[16];return a;
 }
 static String vector(int[] values){return Arrays.toString(values);}
 static String effects(n a){return Arrays.deepToString(a.var_q_a.var_java_util_Vector_a.toArray());}
 public static void main(String[] args)throws Exception{
  Scanner in=new Scanner(new java.io.File(args[0]));for(int r=0;r<148;r++)for(int c=0;c<57;c++)q.table[r][c]=in.nextInt();
  System.out.print("{\\"payloads\\":[");boolean comma=false;
  for(int type:new int[]{2,3,5,10,99})for(int id=0;id<15;id++){
   n a=unit(type==99?3:type);if(type==99){for(int slot=47;slot<=54;slot++)a.var_q_a.i[slot]=7;a.p();}int[] row=s.var_int_arr_arr_a[id+2];if(a.var_q_b.i[row[3]]<=row[4])continue;
   if(comma)System.out.print(",");comma=true;
   q payload=a.var_q_b.q_a(id+2);int cost=q.var_m_a.a(row[2],a,id+2);
   System.out.print("{\\"type\\":"+a.var_int_c+",\\"spell\\":"+id+",\\"stats\\":"+vector(a.var_q_b.i)+",\\"payload\\":"+vector(payload.i)+",\\"cost\\":"+cost+"}");
  }
  System.out.print("],\\"damage\\":[");
  for(int k=0;k<13;k++){
   n a=unit(k>=8?0:5),d=unit(k==3||k==4||k==9?13:0);int id=k==1||k==2||k==3||k==4?1:0;
   if(k==1)d.var_q_b.i[0]=1;if(k==2||k==4||k==5||k==10){d.var_boolean_d=true;d.var_q_b.i[0]=0;}
   if(k==6){a.var_q_a.i[8]=10;a.p();}
   if(k==7){d.var_q_a.i[42]=26;d.p();}
   if(k==11){a.var_q_a.i[40]=1001;a.p();}
   if(k==12){d.var_q_a.i[41]=101;d.p();}
   a.var_q_b.i[2]=a.var_q_b.i[16];a.B=2;
   q payload=a.var_q_b.q_a(k>=6?0:id+2);
   if(k==6){payload.i[33]=2;payload.i[36]=100;payload.i[37]=100;payload.i[38]=50;}
   if(k==9)payload.i[38]=50;
   int[] inputA=a.var_q_b.i.clone(),inputD=d.var_q_b.i.clone();boolean wasDead=d.var_boolean_d;
   long seed=20261026+k;q.var_m_a.random=new Random(seed);q.var_m_a.var_java_util_Vector_n.clear();q.var_m_a.var_java_util_Vector_n.add(new ac(a,0,0,0));d.var_q_b.a(payload);
   int next=q.var_m_a.random.nextInt();if(k>0)System.out.print(",");
   System.out.print("{\\"type\\":"+a.var_int_c+",\\"defender_type\\":"+d.var_int_c+",\\"spell\\":"+(k>=6?-1:id)+",\\"seed\\":"+seed+",\\"attacker\\":"+vector(inputA)+",\\"defender\\":"+vector(inputD)+",\\"payload\\":"+vector(payload.i)+",\\"was_dead\\":"+wasDead+",\\"dead\\":"+d.var_boolean_d+",\\"shattered\\":"+d.var_boolean_i+",\\"attacker_after\\":"+vector(a.var_q_b.i)+",\\"defender_after\\":"+vector(d.var_q_b.i)+",\\"effects\\":"+effects(d)+",\\"counter\\":"+(q.var_m_a.var_java_util_Vector_n.size()>1)+",\\"next_int\\":"+next+"}");
  }
  System.out.print("],\\"turns\\":[");n a=unit(0);a.var_q_b.i[0]=10;a.var_q_b.i[1]=0;
  a.var_q_a.a(3,4,8,10);a.var_q_a.a(16,-1,3,6);a.var_q_a.a(16,-2,2,6);a.var_q_a.a(16,-1,3,6);
  q.var_m_a.random=new Random(20261026);
  for(int turn=0;turn<5;turn++){a.var_q_a.d();if(turn>0)System.out.print(",");System.out.print("{\\"stats\\":"+vector(a.var_q_b.i)+",\\"effects\\":"+effects(a)+"}");}
  System.out.print("],\\"walls\\":[");boolean first=true;
  for(int rank=1;rank<=8;rank++)for(int[] delta:new int[][]{{5,0},{0,5},{-5,0},{0,-5},{5,3},{-5,3},{5,-3},{-5,-3}}){
   n caster=unit(5);caster.H=328;caster.I=328;caster.var_q_b.i[51]=rank*2+1;q.var_m_a.var_java_util_Vector_g.clear();caster.void_a(20+delta[0],20+delta[1]);
   ArrayList<int[]> points=new ArrayList<int[]>();for(aa segment:q.var_m_a.var_java_util_Vector_g)points.add(segment.point);
   if(!first)System.out.print(",");first=false;System.out.print("{\\"rank\\":"+rank+",\\"target\\":"+Arrays.toString(new int[]{20+delta[0],20+delta[1]})+",\\"points\\":"+Arrays.deepToString(points.toArray())+"}");
  }
  System.out.print("],\\"roots\\":[");for(int value=0;value<80;value++){if(value>0)System.out.print(",");System.out.print(q.var_m_a.int_c(value));}System.out.println("]}");
 }
}'''
    replacements = {
        'TRIG_CLASS': o_source[o_source.index('public final class o'):].replace('public final class o', 'static class o', 1),
        'ACTION_TABLE': json.dumps(metadata['action_table']).replace('[', '{').replace(']', '}'),
        'SCALE_METHOD': method(m_source, 'public final int int_d(int n2)'),
        'COST_METHOD': method(m_source, 'public final int a(int n2, n n3, int n4)'),
        'ROOT_METHOD': method(m_source, 'public final int int_c(int n2)'),
        'WALL_METHOD': method(n_source, 'public final void void_a(int n2, int n3)'),
        'AGGREGATE_METHOD': method(q_source, 'public final void a(ab ab2, ab ab3)'),
        'DERIVED_METHOD': method(q_source, 'public final void void_b()'),
        'SKILL_METHOD': method(q_source, 'public final void void_c()'),
        'REBUILD_METHOD': method(q_source, 'public final q a(n n2, ab ab2, ab ab3)'),
        'ADD_METHOD': method(q_source, 'public final void a(int n2, int n3, int n4, int n5)'),
        'TICK_METHOD': method(q_source, 'public final void d()'),
        'BLACK_METHOD': method(q_source, 'public final int int_b()'),
        'WHITE_METHOD': method(q_source, 'public final int int_c()'),
        'PAYLOAD_METHOD': method(q_source, 'public final q q_a(int n2)'),
        'DAMAGE_METHOD': method(q_source, 'public final void a(q q2)'),
    }
    for key, value in replacements.items():
        java = java.replace(key, value)
    build = ROOT / 'build/java-magic-reference'
    build.mkdir(exist_ok=True, parents=True)
    (build / 'MagicReference.java').write_text(java, encoding='utf-8')
    (build / 'sincos').mkdir(exist_ok=True)
    for name in ['sin.int', 'cos.int']:
        shutil.copyfile(ROOT / 'analysis/extracted/raw/sincos' / name, build / 'sincos' / name)
    (build / 'input.txt').write_text('\n'.join(' '.join(map(str, row['values'] + [0])) for row in table['rows']), encoding='utf-8')
    result = run_reference(jdk, build, 'MagicReference', 'input.txt')
    reference = json.loads(result)
    reference['source_sha256'] = metadata['source_sha256']
    reference['method_hashes'] = {key: hashlib.sha256(value.encode()).hexdigest() for key, value in replacements.items() if key.endswith('_METHOD')}
    (ROOT / 'tools/legacy_magic_reference.json').write_text(json.dumps(reference, indent=2) + '\n', encoding='utf-8')
    print(f"Java magic reference: {len(reference['payloads'])} payload/cost cases, {len(reference['damage'])} hits, {len(reference['turns'])} turns")


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--jdk', default='F:/apps/Java')
    generate(parser.parse_args().jdk)
