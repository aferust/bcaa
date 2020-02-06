# bcaa
Simple associative array implementation for D (-betterC) that fits my needs.
 * compatible with betterC.
 * supported key types: string and integral types. 

## Examples:
```d
    import core.stdc.stdio;

    Bcaa!(string, string) aa;

    aa["Stevie"] = "Ray Vaughan";
    aa["Asım Can"] = "Gündüz";
    aa["Dan"] = "Patlansky";
    aa["İlter"] = "Kurcala";
    aa["Ferhat"] = "Kurtulmuş";
    
    assert(aa.remove("Ferhat") == true);
    assert(aa["Ferhat"] == null);
    assert(aa.remove("Foe") == false);
    assert(aa["İlter"] =="Kurcala");

    printf("%s\n",aa["Stevie"].ptr);
    printf("%s\n",aa["Asım Can"].ptr);
    printf("%s\n",aa["Dan"].ptr);

    auto keys = aa.keys;
    foreach(key; keys)
        printf("%s -> %s \n", key.ptr, aa[key].ptr);
    
    keys.free;
    aa.free;

    struct Guitar {
        string brand;
    }

    Bcaa!(int, Guitar) guitars;

    guitars[0] = Guitar("Fender");
    guitars[3] = Guitar("Gibson");
    guitars[356] = Guitar("Stagg");

    assert(guitars[3].brand == "Gibson");

    printf("%s \n", guitars[356].brand.ptr);

    guitars.free;
}
```