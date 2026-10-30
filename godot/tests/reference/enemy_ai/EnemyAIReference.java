import java.util.*;
import java.nio.file.*;
public class EnemyAIReference {
 static class n { int id,t,u,s;boolean var_boolean_d;int[] stats=new int[57];int d(int slot){return stats[slot];} }
 static class s { static int[][] var_int_arr_arr_a=new int[][]{{0, 0, 0, 40, 1, 0, 0}, {1, 0, 0, 43, 1, 0, 0}, {2, 3, 2, 51, 1, 0, 0}, {3, 5, 5, 50, 1, 0, 2}, {2, 2, 4, 54, 2, 1, 1}, {2, 5, 3, 54, 1, 0, 0}, {2, 0, 6, 48, 2, 0, 0}, {2, 10, 15, 54, 3, 1, 1}, {3, 0, 7, 50, 3, 0, 2}, {2, 50, 25, 51, 3, 0, 1}, {2, 6, 20, 54, 4, 1, 1}, {2, 7, 12, 51, 2, 0, 1}, {2, 15, 29, 51, 4, 2, 1}, {2, 0, 20, 47, 2, 0, 0}, {2, 0, 5, 48, 1, 0, 2}, {2, 0, 8, 50, 2, 0, 2}, {3, 0, 5, 47, 1, 0, 2}}; }
 static class ac { n actor;int action,x,y;ac(n a,int b,int c,int d){actor=a;action=b;x=c;y=d;} }
 static class m {
  n var_n_c;Vector<n> var_java_util_Vector_i=new Vector<>();int[] var_int_arr_n=new int[32],var_int_arr_m=new int[32];Random random;ArrayList<ac> queue=new ArrayList<>();
  int int_b(int bound){return Math.abs(random.nextInt()%bound);}
  int a(int mana,n actor,int spell){return mana+mana/2*((actor.d(s.var_int_arr_arr_a[spell][3])-1)/s.var_int_arr_arr_a[spell][4]);}
  boolean b(n actor,n target,int x,int y){return Math.abs(x-actor.t)+Math.abs(y-actor.u)>actor.d(18);}
  void a(ac command){queue.add(command);}
  public final boolean boolean_b() {
        int n2;
        int n3;
        Object var1_1 = null;
        n n4 = null;
        int n5 = 0;
        int n6 = this.var_n_c.d(2);
        if (n6 <= 0) {
            return false;
        }
        int n7 = this.var_n_c.d(1);
        for (n3 = 7; n3 <= 21; ++n3) {
            n2 = n3 - 7 + 2;
            int n8 = this.a(s.var_int_arr_arr_a[n2][2], this.var_n_c, n2);
            if (this.var_n_c.d(s.var_int_arr_arr_a[n2][3]) < s.var_int_arr_arr_a[n2][4] || n7 < n8 || (s.var_int_arr_arr_a[n2][6] & 2) != 0) continue;
            this.var_int_arr_n[n5] = n3 - 7 + 2;
            ++n5;
        }
        if (n5 <= 0) {
            return false;
        }
        n2 = this.var_int_arr_n[this.int_b(n5)];
        n5 = 0;
        for (n3 = 0; n3 < this.var_java_util_Vector_i.size(); ++n3) {
            n n9 = (n)this.var_java_util_Vector_i.elementAt(n3);
            if (n9.var_boolean_d || n9.s == this.var_n_c.s != ((s.var_int_arr_arr_a[n2][6] & 2) != 0) || this.b(this.var_n_c, n9, n9.t, n9.u)) continue;
            this.var_int_arr_m[n5] = n3;
            ++n5;
        }
        if (n5 <= 0) {
            return false;
        }
        n4 = (n)this.var_java_util_Vector_i.elementAt(this.var_int_arr_m[this.int_b(n5)]);
        this.a(new ac(this.var_n_c, 3 + n2 - 2, n4.t, n4.u));
        this.a(new ac(this.var_n_c, 19, 500, 0));
        return true;
    }


 }
 public static void main(String[] args) throws Exception {
  StringBuilder out=new StringBuilder("{\"source\":\"m.boolean_b()\",\"cases\":[");boolean comma=false;
  for(String name:new String[]{"all","low_mana","rank_one","no_magic","out_of_range","dead_target","only_friendly"})for(long seed:new long[]{0,1,2,7,42,20261026}) {
   m ai=new m();ai.random=new Random(seed);n actor=new n();actor.id=1001;actor.s=1;actor.t=23;actor.u=20;actor.stats[2]=10;actor.stats[1]=1000;actor.stats[18]=40;
   for(int slot=46;slot<56;slot++)actor.stats[slot]=7;
   if(name.equals("low_mana"))actor.stats[1]=3;
   if(name.equals("rank_one")){Arrays.fill(actor.stats,46,56,0);actor.stats[51]=1;}
   if(name.equals("no_magic"))Arrays.fill(actor.stats,46,56,0);
   if(name.equals("out_of_range"))actor.stats[18]=1;
   n hero=new n();hero.id=1;hero.t=20;hero.u=20;n ally=new n();ally.id=1000;ally.t=19;ally.u=20;
   if(name.equals("dead_target"))hero.var_boolean_d=true;
   if(name.equals("only_friendly")){hero.s=1;ally.s=1;}
   ai.var_n_c=actor;ai.var_java_util_Vector_i.add(hero);ai.var_java_util_Vector_i.add(ally);ai.var_java_util_Vector_i.add(actor);
   boolean cast=ai.boolean_b();int spell=-1,target=-1;
   if(cast){ac first=ai.queue.get(0);spell=first.action-3;for(n unit:ai.var_java_util_Vector_i)if(unit.t==first.x&&unit.u==first.y)target=unit.id;}
   if(comma)out.append(",");comma=true;
   out.append("{\"scenario\":\"").append(name).append("\",\"seed\":").append(seed).append(",\"cast\":").append(cast).append(",\"spell\":").append(spell).append(",\"target\":").append(target).append(",\"next_int\":").append(ai.random.nextInt()).append("}");
  }
  out.append("]}");Files.writeString(Path.of(args[0]),out.toString());System.out.println("Original enemy AI: 42 spell/target/RNG cases");
 }
}
