/** Simple associative array implementation for D (-betterC)
Copyright:
 Copyright (c) 2020, Ferhat Kurtulmuş.

 License:
   $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).

This file includes parts of dmd/src/dmd/backend/aarray.d

*/

module bcaa;
pragma(LDC_no_moduleinfo);

import core.stdc.stdlib;
import core.stdc.string;

import dvector;

private {
    immutable uint[14] primeList =
    [
        97U,         389U,
        1543U,       6151U,
        24593U,      98317U,
        393241U,     1572869U,
        6291469U,    25165843U,
        100663319U,  402653189U,
        1610612741U, 4294967291U
    ];

    alias hash_t = size_t;

    struct KeyType(K){
        alias Key = K;

        static hash_t getHash(ref const Key key) @nogc nothrow {
            static if(is(K : int)){
                return cast(hash_t)key;
            } else
            static if(is(K == string)){
                hash_t hash = 0;
                foreach(ref v; key)
                    hash = hash * 11 + v;
                return hash;
            } else
            static assert(false, "Unsupported key type!");
        }

        static bool equals(ref const Key k1, ref const Key k2) @nogc nothrow {
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

    private Dvector!(Node*) htable;

    size_t length() @nogc nothrow {
        return nodes;
    }

    private void initTableIfNeeded() @nogc nothrow {
        if(htable.total == 0)
            foreach (i; 0 .. primeList[0])
                htable.pushBack(null);
    }

    void set(ref const K key, ref const V val) @nogc nothrow {
        initTableIfNeeded();

        hash_t keyHash = tkey.getHash(key);
        const pos = keyHash % htable.length;

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
        htable[pos] = newNode;

        ++nodes;

        if (nodes > htable.length * 4){
            rehash();
        }
    }

    private Node* lookup(ref const K key) @nogc nothrow {
        hash_t keyHash = tkey.getHash(key);
        const pos = keyHash % htable.length;

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

    void rehash() @nogc nothrow {
        if (!nodes)
            return;

        size_t newHTableLength = primeList[$ - 1];

        foreach (prime; primeList[0 .. $ - 1]){
            if (nodes <= prime){
                newHTableLength = prime;
                break;
            }
        }

        Dvector!(Node*) newHTable;
        foreach(i; 0..newHTableLength)
            newHTable.pushBack(null);

        foreach (e; htable){
            while (e){
                auto en = e.next;
                auto b = &newHTable[e.hash % newHTableLength];
                e.next = *b;
                *b = e;
                e = en;
            }
        }

        htable.free;
        
        htable = newHTable;
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

    /// returning vector has to be cleaned-up with member free method of Dvector.
    Dvector!K keys() @nogc nothrow {
        Dvector!K ks;

        foreach(i; 0..htable.length){
            auto node = htable[i];
            if(node is null)
                continue;
            Node* tmp = node;
            while(tmp){
                ks.pushBack(tmp.key);
                tmp = tmp.next;
            }
        }

        return ks;
    }

    /// returning vector has to be cleaned-up with member free method of Dvector.
    Dvector!V values() @nogc nothrow {
        Dvector!V vals;

        foreach(i; 0..htable.length){
            auto node = htable[i];
            if(node is null)
                continue;
            Node* tmp = node;
            while(tmp){
                vals.pushBack(tmp.val);
                tmp = tmp.next;
            }
        }

        return vals;
    }
    
    // uses iteration
    bool remove(scope const K key) @nogc nothrow {
        if (!nodes)
            return false;
        const keyHash = tkey.getHash(key);
        const pos = keyHash % htable.length;

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
                return true;
            }
        }
    
        return false;
    }

    // uses recursion
    bool remove2(scope const K key) @nogc nothrow {
        if (!nodes)
            return false;
        
        const keyHash = tkey.getHash(key);
        const pos = keyHash % htable.length;

        Node *recursiveDelete(Node *current, K key, bool* removed) @nogc nothrow {
            if (current == null)
                return null;
            if (keyHash == current.hash && tkey.equals(current.key, key)){
                Node *tmpNext = current.next;
                core.stdc.stdlib.free(current);
                *removed = true;
                return tmpNext;
            }
            current.next = recursiveDelete(current.next, key, removed);
            return current;
        }

        bool removed = false;
        
        htable[pos] = recursiveDelete(htable[pos], key, &removed);
        if(removed){
            --nodes;
            return true;
        }
            
        return false;
    }

    void free() @nogc nothrow {
        foreach (e; htable){
            while (e){
                auto en = e;
                e = e.next;
                core.stdc.stdlib.free(en);
            }
        }
        nodes = 0;
        htable.free;
    }
}

unittest {
    import core.stdc.stdio;
    
    Bcaa!(int, int) aa0;

    foreach (i; 0..1000000){
        aa0[i] = i;
    }

    printf("%d \n", aa0[1000]);

    aa0.free;

    Bcaa!(string, string) aa;

    aa["Stevie"] = "Ray Vaughan";
    aa["Asım Can"] = "Gündüz";
    aa["Dan"] = "Patlansky";
    aa["İlter"] = "Kurcala";
    aa["Ferhat"] = "Kurtulmuş";

    if (auto valptr = "Dan" in aa)
        printf("%s exists!!!!\n", (*valptr).ptr );
    else
        printf("does not exist!!!!\n".ptr);

    assert(aa.remove("Ferhat") == true);
    assert(aa["Ferhat"] == null);
    assert(aa.remove("Foe") == false);
    assert(aa["İlter"] =="Kurcala");

    printf("%s\n",aa["Stevie"].ptr);
    printf("%s\n",aa["Asım Can"].ptr);
    printf("%s\n",aa["Dan"].ptr);
    printf("%s\n",aa["Ferhat"].ptr);

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

    if(auto valPtr = 3 in guitars)
        printf("%s \n", (*valPtr).brand.ptr);

    guitars.free;
}
