/** Simple associative array implementation for D (-betterC)
Copyright:
 Copyright (c) 2020, Ferhat Kurtulmuş.

 License:
   $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).

This file includes parts of
    druntime/blob/master/src/rt/aaA.d
    dmd/src/dmd/backend/aarray.d
    dmd/root/aav.c
*/

module bcaa;

version(LDC){
    pragma(LDC_no_moduleinfo);
}

import core.stdc.stdlib;
import core.stdc.string;

// grow threshold
private enum GROW_NUM = 4;
private enum GROW_DEN = 5;
// shrink threshold
private enum SHRINK_NUM = 1;
private enum SHRINK_DEN = 8;
// grow factor
private enum GROW_FAC = 4;

private enum INIT_NUM = (GROW_DEN * SHRINK_NUM + GROW_NUM * SHRINK_DEN) / 2;
private enum INIT_DEN = SHRINK_DEN * GROW_DEN;

private enum INIT_NUM_BUCKETS = 8;

private enum SHRINK_THR = 10 /* % */;

private {
    alias hash_t = size_t;

    struct KeyType(K){
        alias Key = K;

        static hash_t getHash(Key key) @nogc @safe nothrow pure {
            static if(is(K : int)){
                key ^= (key >> 20) ^ (key >> 12);
                return key ^ (key >> 7) ^ (key >> 4);
            } else
            static if(is(K == string)){
                hash_t hash = 0;
                foreach(ref v; key)
                    hash = hash * 11 + v;
                return hash;
            } else
            static assert(false, "Unsupported key type!");
        }

        static bool equals(ref const Key k1, ref const Key k2) @nogc nothrow pure {
            static if(is(K : int)){
                return k1 == k2;
            } else
            static if(is(K == string)){
                return k1.length == k2.length &&
                    memcmp(k1.ptr, k2.ptr, k1.length) == 0;
            } else
            static assert(false, "Unsupported key type!");
        }
    }
}

struct Bcaa(K, V){
    alias TKey = KeyType!K;

    struct Node {
        Node* next;
        hash_t hash;
        K key;
        V val;
    }

    size_t nodes;
    TKey tkey;

    private Node*[] htable;

    size_t length() @nogc nothrow {
        return nodes;
    }

    bool empty() const pure nothrow @nogc {
        return htable is null || !htable.length;
    }

    private Node*[] allocHtable(size_t sz) @nogc nothrow {
        auto hptr = cast(Node**)malloc(sz * (Node*).sizeof);
        Node*[] _htable = hptr[0..sz];
        _htable[] = null;
        return _htable;
    }

    private void initTableIfNeeded() @nogc nothrow {
        if(htable is null)
            htable = allocHtable(INIT_NUM_BUCKETS);
    }

    void set(ref const K key, ref const V val) @nogc nothrow {
        initTableIfNeeded();

        hash_t keyHash = tkey.getHash(key);
        const size_t pos = keyHash % htable.length;

        Node *list = htable[pos];
        Node *temp = list;

        while(temp){
            if(tkey.equals(temp.key, key)){
                temp.val = val;
                return;
            }
            temp = temp.next;
        }

        Node *newNode = cast(Node*)malloc(Node.sizeof);
        newNode.key = key;
        newNode.val = val;
        newNode.hash = keyHash;
        newNode.next = list;

        if ((nodes + 1) * GROW_DEN > htable.length * GROW_NUM)
            grow();
        
        htable[pos] = newNode;

        ++nodes;
    }

    private Node* lookup(ref const K key) @nogc nothrow {
        hash_t keyHash = tkey.getHash(key);
        const size_t pos = keyHash % htable.length;

        Node* list = htable[pos];
        Node* temp = list;
        while(temp){
            if(keyHash == temp.hash && tkey.equals(temp.key, key)){
                return temp;
            }
            temp = temp.next;
        }
        return null;
    }

    void resize(size_t sz) @nogc nothrow {
        if(sz == htable.length)
            return;
        Node*[] newHTable = allocHtable(sz);

        foreach (ref e; htable){
            while (e){
                auto en = e.next;
                auto b = &newHTable[e.hash % sz];
                e.next = *b;
                *b = e;
                e = en;
            }
        }

        core.stdc.stdlib.free(htable.ptr);
        htable = newHTable;
    }

    void rehash() @nogc nothrow {
        if (!empty)
            return;
        resize(nextpow2(INIT_DEN * length / INIT_NUM));
    }

    void grow() @nogc nothrow {
        if (nodes * SHRINK_DEN > GROW_FAC * htable.length * SHRINK_NUM){
            resize(GROW_FAC * htable.length);
            //import core.stdc.stdio;
            //printf("grow\n");
        }
            
    }

    void shrink() @nogc nothrow {
        const ulong load = nodes * 100 / htable.length;
        if (htable.length > INIT_NUM_BUCKETS && load < SHRINK_THR){
            resize(htable.length / GROW_FAC);
            //import core.stdc.stdio;
            //printf("shrink\n");
        }   
    }

    bool remove(scope const K key) @nogc nothrow {
        if (!nodes)
            return false;
        const keyHash = tkey.getHash(key);
        const size_t pos = keyHash % htable.length;

        Node* current, previous;
        previous = null;
        for (current = htable[pos];
            current != null;
            previous = current,
            current = current.next) {
            
            if (keyHash == current.hash && tkey.equals(current.key, key)){
                if (previous == null) {
                    htable[pos] = current.next;
                } else {
                    previous.next = current.next;
                }
                core.stdc.stdlib.free(current);
                current = null;
                --nodes;
                shrink();
                return true;
            }
        }
    
        return false;
    }

    V get(ref const K key) @nogc nothrow {
        if(auto ret = opBinaryRight!"in"(key))
            return *ret;
        return V.init;
    }

    V opIndex(scope const K key) @nogc nothrow {
        return get(key);
    }

    void opIndexAssign(scope const V value, scope const K key) @nogc nothrow {
        set(key, value);
    }

    V* opBinaryRight(string op)(scope const K key) @nogc nothrow {
        static if (op == "in"){
            if(auto node = lookup(key))
                return &node.val;
            return null;
        } else
        static assert(0, "Operator "~op~" not implemented");
    }

    /// returning slice must be deallocated like free(keys.ptr);
    K[] keys() @nogc nothrow {
        K[] ks = (cast(K*)malloc(nodes * K.sizeof))[0..nodes];
        size_t j;
        foreach(i; 0..htable.length){
            auto node = htable[i];
            if(node is null)
                continue;
            Node* tmp = node;
            while(tmp){
                ks[j++] = tmp.key;
                tmp = tmp.next;
            }
        }

        return ks;
    }

    /// returning slice must be deallocated like free(values.ptr);
    V[] values() @nogc nothrow {
        V[] vals = (cast(V*)malloc(nodes * V.sizeof))[0..nodes];
        size_t j;
        foreach(i; 0..htable.length){
            auto node = htable[i];
            if(node is null)
                continue;
            Node* tmp = node;
            while(tmp){
                vals[j++] = tmp.val;
                tmp = tmp.next;
            }
        }

        return vals;
    }

    void clear() @nogc nothrow {
        foreach (ref e; htable){
            while (e){
                auto en = e;
                e = e.next;
                core.stdc.stdlib.free(en);
            }
        }
        nodes = 0;
    }

    void free() @nogc nothrow {
        clear();
        core.stdc.stdlib.free(htable.ptr);
        htable = null;
    }

    // TODO: .byKey(), .byValue(), .byKeyValue()
}

private size_t nextpow2(const size_t n) pure nothrow @nogc {
    import core.bitop : bsr;

    if (!n)
        return 1;

    const isPowerOf2 = !((n - 1) & n);
    return 1 << (bsr(n) + !isPowerOf2);
}

unittest {
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
    foreach(key; keys)
        printf("%s -> %s \n", key.ptr, aa1[key].ptr);
    core.stdc.stdlib.free(keys.ptr);
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
}