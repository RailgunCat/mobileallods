"""Compile recovered Java methods in isolation to generate independent goldens.

Requires local decompiled sources and a JDK. Does not run the original MIDlet.
No Java is needed for normal Godot play or its checked-in reference tests.
"""
import argparse
import hashlib
import json
from pathlib import Path

from java_reference import method, run_reference

ROOT = Path(__file__).resolve().parent.parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--jdk', default='F:/apps/Java')
    args = parser.parse_args()
    m_source = (ROOT / 'analysis/decompiled/m.java').read_text(encoding='utf-8')
    q_source = (ROOT / 'analysis/decompiled/q.java').read_text(encoding='utf-8')
    n_source = (ROOT / 'analysis/decompiled/n.java').read_text(encoding='utf-8')
    metadata = json.loads((ROOT / 'tools/legacy_gameplay.json').read_text(encoding='utf-8'))
    constants = json.loads((ROOT / 'analysis/extracted/constants.json').read_text(encoding='utf-8'))
    table = json.loads((ROOT / 'analysis/extracted/tables/abilities.txt.json').read_text(encoding='utf-8'))
    maps = [(p.name.removesuffix('.map.json'), json.loads(p.read_text(encoding='utf-8'))) for p in sorted((ROOT / 'analysis/extracted/maps').glob('*.json'))]
    build = ROOT / 'build/java-reference'
    build.mkdir(parents=True, exist_ok=True)
    source = '''import java.util.*;
public class LegacyReference {
 static class m {
  byte[] var_byte_arr_o;
  byte[][] var_byte_arr_arr_a, var_byte_arr_arr_c;
  int var_int_n, var_int_o;
  TABLE_METHOD
  COLLISION_METHOD
 }
 static class ab {
  int var_int_a, b;
  ab[] var_ab_arr_a = new ab[10];
  ab(int id) {var_int_a=id; b=id%3+1;}
  int b() {return (var_int_a-12)/6;}
 }
 static class s {static int[][][] var_int_arr_arr_arr_a, var_int_arr_arr_arr_b;}
 static class n {
  q var_q_a;
  static m var_m_a;
  int var_int_c=0, var_int_d=0, var_int_a=10, var_int_b=10;
  PIXEL_METHOD
 }
 static class q {
  static m var_m_a = new m();
  static int[][] table = new int[148][57];
  n var_n_a;
  int[] i = new int[57];
  Vector<int[]> var_java_util_Vector_a = new Vector<int[]>();
  int[] int_arr_a(int id) {return table[id];}
  AGGREGATE_METHOD
  DERIVED_METHOD
  SKILL_METHOD
 }
 public static void main(String[] args) throws Exception {
  Scanner in = new Scanner(new java.io.File(args[0]));
  m world = new m(); world.var_byte_arr_o = new byte[46];
  for(int i=0;i<46;i++)world.var_byte_arr_o[i]=in.nextByte();
  int maps=in.nextInt();byte[][] firstTerrain=null;int firstW=0,firstH=0;
  for(int k=0;k<maps;k++) {
   String name=in.next(); int w=in.nextInt(),h=in.nextInt();world.var_int_n=w;
   world.var_byte_arr_arr_a=new byte[h][w];world.var_byte_arr_arr_c=new byte[h][w];
   for(int y=0;y<h;y++)for(int x=0;x<w;x++)world.var_byte_arr_arr_a[y][x]=in.nextByte();
   // Exactly the legacy loader's traversal. Invalid inputs must fail loudly.
   for(int y=0;y<h;y++)for(int x=0;x<w;x++)world.b(y,x);
   if(name.equals("1")){firstTerrain=world.var_byte_arr_arr_c;firstW=w;firstH=h;}
   System.out.print("map "+name+" ");
   for(byte[] row:world.var_byte_arr_arr_c)for(byte cell:row)System.out.print(cell);
   System.out.println();
  }
  for(int r=0;r<148;r++)for(int c=0;c<57;c++)q.table[r][c]=in.nextInt();
  for(int type=0;type<4;type++) {
   n unit=new n();unit.var_q_a=new q();unit.var_q_a.i=q.table[90+type].clone();
   q stats=new q();stats.var_n_a=unit;
   stats.a(new ab(12+type*6),new ab(type*3));stats.void_b();stats.void_c();
   stats.i[18]=Math.max(0,Math.min(40,stats.i[18]));
   stats.i[0]=stats.i[14];stats.i[1]=stats.i[15];stats.i[2]=stats.i[16];
   System.out.print("stats "+type+" ");
   for(int value:stats.i)System.out.print(value+",");System.out.println();
  }
  s.var_int_arr_arr_arr_a=new int[18][4][2];s.var_int_arr_arr_arr_b=new int[18][4][2];
  for(int type=0;type<18;type++)for(int dir=0;dir<4;dir++)for(int axis=0;axis<2;axis++)s.var_int_arr_arr_arr_a[type][dir][axis]=in.nextInt();
  for(int type=0;type<18;type++)for(int dir=0;dir<4;dir++)for(int axis=0;axis<2;axis++)s.var_int_arr_arr_arr_b[type][dir][axis]=in.nextInt();
  world.var_byte_arr_arr_c=firstTerrain;world.var_int_n=firstW;world.var_int_o=firstH;n.var_m_a=world;
  n hero=new n();StringBuilder pixels=new StringBuilder();
  for(int dir=0;dir<4;dir++) {hero.var_int_d=dir;for(int y=0;y<firstH*16;y+=8)for(int x=0;x<firstW*16;x+=8)pixels.append(hero.boolean_a(x,y)?'1':'0');}
  System.out.println("pixels 1 "+pixels);
 }
}'''
    replacements = {
        'COLLISION_METHOD': method(m_source, 'public final void b(int n2, int n3)'),
        'TABLE_METHOD': method(m_source, 'public final int int_d(int n2)'),
        'AGGREGATE_METHOD': method(q_source, 'public final void a(ab ab2, ab ab3)'),
        'DERIVED_METHOD': method(q_source, 'public final void void_b()'),
        'SKILL_METHOD': method(q_source, 'public final void void_c()'),
        'PIXEL_METHOD': method(n_source, 'public final boolean boolean_a(int n2, int n3)'),
    }
    for key, value in replacements.items():
        source = source.replace(key, value)
    (build / 'LegacyReference.java').write_text(source, encoding='utf-8')
    inputs = [' '.join(map(str, constants['tile_image_ids'])), str(len(maps))]
    for name, data in maps:
        inputs.append(f"{name} {data['width']} {data['height']}")
        inputs.extend(' '.join(map(str, row)) for row in data['source_tile_ids'])
    for entry in table['rows']:
        values = entry['values'] + [0] * (57 - len(entry['values']))
        inputs.append(' '.join(map(str, values)))
    for key in ['frame_sizes', 'origins']:
        for unit in metadata['exploration']['units']:
            for direction in unit[key][:4]:
                inputs.append(' '.join(map(str, direction)))
    (build / 'input.txt').write_text('\n'.join(inputs), encoding='utf-8')
    result = run_reference(args.jdk, build, 'LegacyReference', 'input.txt')
    golden = {'source_sha256': metadata['source_sha256'], 'maps': {}, 'starting_stats': {}}
    for line in result.splitlines():
        kind, key, value = line.split(' ', 2)
        if kind == 'map':
            terrain = bytes(map(int, value))
            golden['maps'][key] = {'sha256': hashlib.sha256(terrain).hexdigest(), 'blocked_cells': sum(terrain)}
        elif kind == 'stats':
            golden['starting_stats'][key] = list(map(int, value.rstrip(',').split(',')))
        elif kind == 'pixels':
            golden['exploration_map1'] = {'sample_step': 8, 'sha256': hashlib.sha256(bytes(map(int, value))).hexdigest()}
    output = ROOT / 'tools/legacy_gameplay_reference.json'
    output.write_text(json.dumps(golden, indent=2) + '\n', encoding='utf-8')
    print(f"Java reference: {len(golden['maps'])} collision grids; {len(golden['starting_stats'])} equipped stat vectors; map 1 pixel collision in 4 directions -> {output}")


if __name__ == '__main__':
    main()
