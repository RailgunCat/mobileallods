"""Run actual recovered dungeon-generation methods, with inert unit presentation."""
import argparse
import hashlib
import json
from pathlib import Path
from java_reference import method, run_reference

ROOT = Path(__file__).resolve().parents[1]


def literal(value):
    return json.dumps(value, separators=(',', ':')).replace('[', '{').replace(']', '}')


def generate(jdk):
    source = (ROOT / 'analysis/decompiled/m.java').read_text(encoding='utf-8')
    metadata = json.loads((ROOT / 'tools/legacy_gameplay.json').read_text(encoding='utf-8'))
    travel = metadata['travel']
    replacements = {
        'ROOM_METHOD': method(source, 'public final int int_a(int n2, int n3, int n4, int n5)'),
        'CARVE_METHOD': method(source, 'public final byte[][] byte_arr_arr_a(int n2, int n3, int n4, int n5, int n6, int n7)'),
        'EXPAND_METHOD': method(source, 'public final void af()'),
        'GENERATE_METHOD': method(source, 'public final void c(int n2, int n3)'),
        'MASK_METHOD': method(source, 'public final void a(byte[][] byArray, byte[][] byArray2)'),
        'RECT_METHOD': method(source, 'public final void a(byte[][] byArray, int n2, int n3, int n4, int n5)'),
        'PLACE_METHOD': method(source, 'public final void void_a(n n2, int n3, int n4)'),
        'NEAREST_METHOD': method(source, 'public final byte[] byte_arr_a(n n2, int n3, int n4)'),
        'PICKUP_METHOD': method(source, 'public final void void_b(int n2)'),
    }
    # CFR omits the narrowing cast on this byte-valued conditional; restore the
    # cast without changing either branch or its random draws.
    replacements['EXPAND_METHOD'] = replacements['EXPAND_METHOD'].replace('? 5 : 6', '? (byte)5 : (byte)6')
    pickups = []
    for rows in metadata['economy']['pickups']:
        pickups.append([[p['pickup_id'], *p['position_pixels'], p['script_id'], *p['items'], *([-p['gold']] if p['gold'] else [])] for p in rows])
    java = '''import java.util.*;
public class TravelReference {
 static class n {
  static m var_m_a;int H,I,t,u,j,k,var_int_c;
  n(int x,int y,int type,int group,int flag,boolean hostile,int a,int b,int c){var_int_c=type;int[] f=SHAPES[type];j=f[0];k=f[1];H=x;I=y;}
  void h(){H=t*16+j*8;I=u*16+k*8;}
  void k(){for(int y=0;y<k;y++)for(int x=0;x<j;x++)var_m_a.var_byte_arr_arr_c[u+y][t+x]=-1;}
 }
 static int[][] SHAPES=new int[][]FOOTPRINTS;
 static class m {
  byte[][][] var_byte_arr_arr_arr_a;byte[][] var_byte_arr_arr_a,var_byte_arr_arr_c;byte[] var_byte_arr_m=null;
  byte[] var_byte_arr_c=new byte[27],var_byte_arr_d=new byte[50],var_byte_arr_b=new byte[169];
  int[][][] var_int_arr_arr_arr_g;Random var_java_util_Random_c;long[] var_long_arr_a=new long[12];int ai,aj;byte var_byte_a;
  int[][] var_int_arr_arr_k=new int[][]SPECS,var_int_arr_arr_l=new int[][]EXITS,var_int_arr_arr_m=new int[][]POPULATION;
  int[][][] var_int_arr_arr_arr_e=new int[][][]SCRIPTS,var_int_arr_arr_arr_f=new int[][][]PICKUPS;
  Vector<int[]> var_java_util_Vector_e=new Vector<>(),var_java_util_Vector_d=new Vector<>(),var_java_util_Vector_h=new Vector<>();Vector<n> var_java_util_Vector_c=new Vector<>();
  ROOM_METHOD
  CARVE_METHOD
  EXPAND_METHOD
  GENERATE_METHOD
  MASK_METHOD
  RECT_METHOD
  PLACE_METHOD
  NEAREST_METHOD
  PICKUP_METHOD
 }
 public static void main(String[] args) {
  System.out.print("{\\"dungeons\\":[");boolean comma=false;
  for(int id=0;id<12;id++)for(long seed:new long[]{1,20261027,987654321}) {
   m world=new m();n.var_m_a=world;Arrays.fill(world.var_byte_arr_b,(byte)1);world.var_long_arr_a[id]=seed;world.c(-id-1,0);
   ArrayList<int[]> units=new ArrayList<>();for(n actor:world.var_java_util_Vector_c)units.add(new int[]{actor.H,actor.I,actor.var_int_c});
   for(byte[] row:world.var_byte_arr_arr_c)for(int x=0;x<row.length;x++)if(row[x]<0)row[x]=0;
   if(comma)System.out.print(",");comma=true;
   System.out.print("{\\"map_id\\":"+(-id-1)+",\\"seed\\":"+seed+",\\"entry\\":["+world.ai+","+world.aj+","+world.var_byte_a+"],\\"tiles\\":"+Arrays.deepToString(world.var_byte_arr_arr_a)+",\\"collision\\":"+Arrays.deepToString(world.var_byte_arr_arr_c)+",\\"units\\":"+Arrays.deepToString(units.toArray())+",\\"scripts\\":"+Arrays.deepToString(world.var_java_util_Vector_e.toArray())+",\\"triggers\\":"+Arrays.deepToString(world.var_java_util_Vector_d.toArray())+",\\"pickups\\":"+Arrays.deepToString(world.var_java_util_Vector_h.toArray())+",\\"next_int\\":"+world.var_java_util_Random_c.nextInt()+"}");
  }
  System.out.println("]}");
 }
}
'''
    constants = {
        'FOOTPRINTS': metadata['unit_footprints'],
        'SPECS': [[p['room_rows'], p['room_columns'], p['minimum_rooms'], p['unused']] for p in travel['dungeon_specs']],
        'EXITS': travel['dungeon_exits'],
        'POPULATION': [[v for p in rows for v in (p['chance'], p['unit_type'])] for rows in travel['dungeon_population']],
        'SCRIPTS': travel['dungeon_scripts'], 'PICKUPS': pickups,
    }
    for key, value in {**replacements, **{k: literal(v) for k, v in constants.items()}}.items():
        java = java.replace(key, value)
    folder = ROOT / 'build/java-travel-reference'
    folder.mkdir(parents=True, exist_ok=True)
    (folder / 'TravelReference.java').write_text(java, encoding='utf-8')
    result = run_reference(jdk, folder, 'TravelReference')
    data = json.loads(result)
    data['source_sha256'] = metadata['source_sha256']
    data['method_hashes'] = {key: hashlib.sha256(value.encode()).hexdigest() for key, value in replacements.items()}
    (ROOT / 'tools/legacy_travel_reference.json').write_text(json.dumps(data, indent=2) + '\n', encoding='utf-8')
    print(f"Java travel reference: {len(data['dungeons'])} complete generated dungeons")


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--jdk', default='F:/apps/Java')
    generate(parser.parse_args().jdk)
