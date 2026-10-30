import java.util.*;
/** Independent execution of m.java victory drops (1294-1317) and int_d.
 * Input contains the recovered mage reward row and s.var_int_arr_g tiers.
 * The video is a random outcome, not a three-item limit. */
public class MageLootReference {
  static int scale(int map) { int value = 100; for (int i=0;i<map;i++) value=value*11/10; return value; }
  static int bounded(Random rng, int bound) { return Math.abs(rng.nextInt()%bound); }
  public static void main(String[] args) throws Exception {
    Scanner in = new Scanner(new java.io.File(args[0]));
    int minimum=in.nextInt(), maximum=in.nextInt();
    int[] tiers=new int[41], drops=new int[41];
    for(int i=0;i<41;i++) tiers[i]=in.nextInt();
    for(int i=0;i<41;i++) drops[i]=in.nextInt();
    System.out.print("{\"cases\":["); boolean comma=false;
    for(int luck:new int[]{0,60,165}) for(int seed=0;seed<8;seed++) {
      Random rng=new Random(seed); int factor=scale(6);
      int gold=(minimum+bounded(rng,maximum-minimum+1))*factor/100;
      ArrayList<Integer> items=new ArrayList<>();
      for(int id=0;id<41;id++) {
        if(drops[id]>=0 && (tiers[id]>6 || bounded(rng,10000)>=drops[id]*factor*(100+luck)/10000)) continue;
        items.add(id);
      }
      if(comma) System.out.print(","); comma=true;
      System.out.print("{\"luck\":"+luck+",\"seed\":"+seed+",\"gold\":"+gold+",\"items\":"+items+",\"next_int\":"+rng.nextInt()+"}");
    }
    System.out.println("]}");
  }
}
