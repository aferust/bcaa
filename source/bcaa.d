module bcaa;
pragma(LDC_no_moduleinfo);

import core.stdc.stdlib;

import dvector;

struct Bcaa(K, V, size_t tableSize = 16) {
    struct Node {
        K key;
        V val;
        Node* next;
    }

    private Node*[tableSize] htable;
    
    private uint hashCode(K key) @nogc nothrow {
        static if(is(K : int)){
            if(key<0)
                return -cast(uint)(key % htable.length);
            return cast(uint)(key % htable.length);
        } else
        static if(is(K == string)){
            uint hashval;
            foreach (i, char c; key)
                hashval = c + 31 * hashval;
            return hashval % htable.length;
        } else {
            static assert(false, "Unsupported key type!");
        }
    }

    void set(K key, V val) @nogc nothrow {
        uint pos = hashCode(key);
        Node *list = htable[pos];
        Node *temp = list;

        while(temp){
            if(temp.key == key){
                temp.val = val;
                return;
            }
            temp = temp.next;
        }
        Node *newNode = cast(Node*)malloc(Node.sizeof);
        newNode.key = key;
        newNode.val = val;
        newNode.next = list;
        htable[pos] = newNode;
    }

    private Node* lookup(K key) @nogc nothrow {
        immutable pos = hashCode(key);
        Node* list = htable[pos];
        Node* temp = list;
        while(temp){
            if(temp.key == key){
                return temp;
            }
            temp = temp.next;
        }
        return null;
    }

    V get(K key) @nogc nothrow {
        const node = lookup(key);
        if(node !is null)
            return node.val;
        return V.init;
    }

    V opIndex(K key) @nogc nothrow {
        return get(key);
    }

    void opIndexAssign(V value, K key) @nogc nothrow {
        set(key, value);
    }

    V opBinaryRight(string op)(K key){
        static if (op == "in"){
            return get(key);
        } else
        static assert(0, "Operator "~op~" not implemented");
    }

    /// returning vector has to be cleaned-up with member free method of Dvector.
    Dvector!K keys() @nogc nothrow {
        Dvector!K ks;

        foreach(i; 0..tableSize){
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

        foreach(i; 0..tableSize){
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
    bool remove(K key) @nogc nothrow {
        foreach(i; 0..tableSize){
            Node* current, previous;
            previous = null;
            for (current = htable[i];
                current != null;
                previous = current,
                current = current.next) {

                if (current.key == key) {
                    if (previous == null) {
                        htable[i] = current.next;
                    } else {
                        previous.next = current.next;
                    }
                    core.stdc.stdlib.free(current);
                    current = null;
                    return true;
                }
            }
        }
        return false;
    }

    // uses recursion
    bool remove2(K key) @nogc nothrow {

        Node *recursiveDelete(Node *current, K key, bool* removed) @nogc nothrow {
            if (current == null)
                return null;
            if (current.key == key) {
                Node *tmpNext = current.next;
                core.stdc.stdlib.free(current);
                *removed = true;
                return tmpNext;
            }
            current.next = recursiveDelete(current.next, key, removed);
            return current;
        }

        bool removed = false;

        foreach(i; 0..tableSize){
            htable[i] = recursiveDelete(htable[i], key, &removed);
            if(removed)
                return true;
        }
        return false;
    }

    void free() @nogc nothrow {
        auto _keys = keys();
        foreach (key; _keys)
            core.stdc.stdlib.free(lookup(key));
        _keys.free;
    }
}

unittest {
    import core.stdc.stdio;

    Bcaa!(string, string) aa;

    aa["Stevie"] = "Ray Vaughan";
    aa["Asım Can"] = "Gündüz";
    aa["Dan"] = "Patlansky";
    aa["İlter"] = "Kurcala";
    aa["Ferhat"] = "Kurtulmuş";
    
    if (auto val = "key1" in aa)
        printf("exist!!!!\n".ptr);
    else
        printf("does not exist!!!!\n".ptr);

    assert(aa.remove("Ferhat") == true);
    assert(aa["Ferhat"] == null);
    assert(aa.remove("Foe") == false);
    assert(aa["İlter"] =="Kurcala");

    printf("%s\n",aa["Stevie"].ptr);
    printf("%s\n",aa["Asım Can"].ptr);
    printf("%s\n",aa["Dan"].ptr);

    auto _keys = aa.keys;
    foreach(key; _keys)
        printf("%s -> %s \n", key.ptr, aa[key].ptr);
    _keys.free;
    
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
