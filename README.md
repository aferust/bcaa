# bcaa
Simple associative array implementation for D (-betterC). Actually, this is a simplified betterC port of druntime/blob/master/src/rt/aaA.d
 * betterC port of druntime/blob/master/src/rt/aaA
 * memory management using any memory allocator (pureMalloc-based one is default).

## Use below subconfiguration for betterC in your dub.json
```json
"subConfigurations": {
        "bcaa": "betterC"
}
```

## Examples:
```d
    import bcaa;
    import bcaa: Mallocator;

    import core.stdc.stdio;
    import core.stdc.time;

    clock_t begin = clock();

    Bcaa!(int, int) aa0;

    foreach (i; 0..1000000){
        aa0[i] = i;
    }

    foreach (i; 2000..1000000){
        aa0.remove(i);
    }

    printf("%d \n", aa0[1000]);
    aa0.free;

    clock_t end = clock(); printf("Elapsed time: %f \n", cast(double)(end - begin) / CLOCKS_PER_SEC);

    Bcaa!(string, string) aa1;

    aa1["Stevie"] = "Ray Vaughan";
    aa1["Asım Can"] = "Gündüz";
    aa1["Dan"] = "Patlansky";
    aa1["İlter"] = "Kurcala";
    aa1["Ferhat"] = "Kurtulmuş";

    foreach(pair; aa1){
        writeln(*pair.keyp, " -> ", *pair.valp);
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

    aa1.free;

    struct Guitar {
        string brand;
    }

    Bcaa!(int, Guitar) guitars;

    guitars[0] = Guitar("Fender");
    guitars[3] = Guitar("Gibson");
    guitars[356] = Guitar("Stagg");

    assert(guitars[3].brand == "Gibson");

    printf("%s \n", guitars[356].brand.ptr);

    if(auto valPtr = 3 in guitars)
        printf("%s \n", (*valPtr).brand.ptr);

    guitars.free;

```