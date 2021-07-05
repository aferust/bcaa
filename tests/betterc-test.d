module betterc_test;

import bcaa;

import core.stdc.stdio;
import core.stdc.time;
import std.experimental.allocator;
import std.experimental.allocator.mallocator : Mallocator;

extern(C) void main() @nogc
{
  clock_t begin = clock();
  {
    Bcaa!(int, int) aa0;
    scope(exit) aa0.free;

    foreach (i; 0..1000_000){
      aa0[i] = i;
    }

    foreach (i; 2000..1000_000){
      aa0.remove(i);
    }

    printf("%d \n", aa0[1000]);
  }
  clock_t end = clock(); printf("Elapsed time: %f \n", cast(double)(end - begin) / CLOCKS_PER_SEC);

  {
    Bcaa!(string, string) aa1;
    scope(exit) aa1.free;

    aa1["Stevie"] = "Ray Vaughan";
    aa1["Asım Can"] = "Gündüz";
    aa1["Dan"] = "Patlansky";
    aa1["İlter"] = "Kurcala";
    aa1["Ferhat"] = "Kurtulmuş";

    foreach(pair; aa1){
      printf("%s -> %s", (*pair.keyp).ptr, (*pair.valp).ptr);
    }

    if (auto valptr = "Dan" in aa1)
      printf("%s exists!!!!\n", (*valptr).ptr );
    else
      printf("does not exist!!!!\n".ptr);

    assert(aa1.remove("Ferhat") == true);
    assert(aa1["Ferhat"] == null);
    assert(aa1.remove("Foe") == false);
    assert(aa1["İlter"] =="Kurcala");

    aa1.rehash();

    printf("%s\n",aa1["Stevie"].ptr);
    printf("%s\n",aa1["Asım Can"].ptr);
    printf("%s\n",aa1["Dan"].ptr);
    printf("%s\n",aa1["Ferhat"].ptr);

    auto keys = aa1.keys;
    scope(exit) Mallocator.instance.dispose(keys);
    foreach(key; keys)
      printf("%s -> %s \n", key.ptr, aa1[key].ptr);

    struct Guitar {
      string brand;
    }

    Bcaa!(int, Guitar) guitars;
    scope(exit) guitars.free;

    guitars[0] = Guitar("Fender");
    guitars[3] = Guitar("Gibson");
    guitars[356] = Guitar("Stagg");

    assert(guitars[3].brand == "Gibson");

    printf("%s \n", guitars[356].brand.ptr);

    if(auto valPtr = 3 in guitars)
      printf("%s \n", (*valPtr).brand.ptr);
  }

  // Test "in" works for AA without allocated storage.
  {
    Bcaa!(int, int) emptyMap;
    assert(0 !in emptyMap);

  }

  // Try to force a memory leak - issue #5
  {
    struct S {
      int x;
      int y;
      string txt;
    }

    Bcaa!(int, S) aas;
    scope(exit) aas.free;

    for(int i = 1024; i < 2048; i++) {
      aas[i] = S(i, i*2, "caca\0");
    }
    aas[100] = S(10, 20, "caca\0");

    printf(".x=%d .y%d %s\n", aas[100].x, aas[100].y, aas[100].txt.ptr);

    for(int i = 1024; i < 2048; i++) {
      aas.remove(i);
    }
  }
}

