/** Simple associative array implementation for D (-betterC)

The author of the original implementation: Martin Nowak

Copyright:
 Copyright (c) 2020, Ferhat Kurtulmuş.

 License:
   $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).

Simplified betterC port of druntime/blob/master/src/rt/aaA.d
*/

module bcaa;

version(LDC){
    version(D_BetterC){
        pragma(LDC_no_moduleinfo);
    }
}

import std.experimental.allocator.common : stateSize;

import core.stdc.string;

// grow threshold
private enum GROW_NUM = 4;
private enum GROW_DEN = 5;
// shrink threshold
private enum SHRINK_NUM = 1;
private enum SHRINK_DEN = 8;
// grow factor
private enum GROW_FAC = 4;
// growing the AA doubles it's size, so the shrink threshold must be
// smaller than half the grow threshold to have a hysteresis
static assert(GROW_FAC * SHRINK_NUM * GROW_DEN < GROW_NUM * SHRINK_DEN);
// initial load factor (for literals), mean of both thresholds
private enum INIT_NUM = (GROW_DEN * SHRINK_NUM + GROW_NUM * SHRINK_DEN) / 2;
private enum INIT_DEN = SHRINK_DEN * GROW_DEN;

private enum INIT_NUM_BUCKETS = 8;
// magic hash constants to distinguish empty, deleted, and filled buckets
private enum HASH_EMPTY = 0;
private enum HASH_DELETED = 0x1;
private enum HASH_FILLED_MARK = size_t(1) << 8 * size_t.sizeof - 1;

private {
    alias hash_t = size_t;

    struct KeyType(K){
        alias Key = K;

        static hash_t getHash(scope const Key key) @nogc @safe nothrow pure {
            return key.hashOf;
        }

        static bool equals(scope const Key k1, scope const Key k2) @nogc nothrow pure {
            static if(is(K == const(char)*)){
                return strlen(k1) == strlen(k2) &&
                    strcmp(k1, k2) == 0;
            } else static if(is(K == string)){
                return strlen(k1.ptr) == strlen(k2.ptr) &&
                    strcmp(k1.ptr, k2.ptr) == 0;
            } else {
                return k1 == k2;
            }
        }
    }
}

/// mallocator code BEGINS

// based on std.experimental.allocator.mallocator and 
// https://github.com/submada/basic_string/blob/main/src/basic_string/package.d:

struct Mallocator{
	import std.experimental.allocator.common : platformAlignment;

	enum uint alignment = platformAlignment;

	static void[] allocate(size_t bytes)@trusted @nogc nothrow pure{
		import core.memory : pureMalloc;
		if (!bytes) return null;
		auto p = pureMalloc(bytes);
		return p ? p[0 .. bytes] : null;
	}

	static bool deallocate(void[] b)@system @nogc nothrow pure{
		import core.memory : pureFree;
		pureFree(b.ptr);
		return true;
	}

    static bool deallocate(void* b)@system @nogc nothrow pure{
		import core.memory : pureFree;
		pureFree(b);
		return true;
	}

	static bool reallocate(ref void[] b, size_t s)@system @nogc nothrow pure{
		import core.memory : pureRealloc;
		if (!s){
			// fuzzy area in the C standard, see http://goo.gl/ZpWeSE
			// so just deallocate and nullify the pointer
			deallocate(b);
			b = null;
			return true;
		}

		auto p = cast(ubyte*) pureRealloc(b.ptr, s);
		if (!p) return false;
		b = p[0 .. s];
		return true;
	}

	static Mallocator instance;
}

T[] makeArray(T, Allocator)(auto ref Allocator alloc, size_t length){
    return cast(T[])alloc.allocate(length * T.sizeof);
}

T* make(T, Allocator)(auto ref Allocator alloc){
    return cast(T*)(alloc.allocate(T.sizeof).ptr);
}

void dispose(A, T)(auto ref A alloc, auto ref T[] array){
    alloc.deallocate(cast(void[])array);
}

void dispose(A, T)(auto ref A alloc, auto ref T* p){
    alloc.deallocate(cast(void*)p);
}

/// mallocator code ENDS

struct Bcaa(K, V, Allocator = Mallocator) {

    struct Node{
        K key;
        V val;
    }

    struct Bucket {
    private pure nothrow @nogc:
        size_t hash;
        Node* entry;
        @property bool empty() const @nogc nothrow {
            return hash == HASH_EMPTY;
        }

        @property bool deleted() const @nogc nothrow {
            return hash == HASH_DELETED;
        }

        @property bool filled() const @safe @nogc nothrow {
            return cast(ptrdiff_t) hash < 0;
        }
    }

    private Bucket[] buckets;

    uint firstUsed;
    uint used;
    uint deleted;

    alias TKey = KeyType!K;
    TKey tkey;

    enum bool hasStatelessAllocator = (stateSize!Allocator == 0);
    static if (hasStatelessAllocator)
    {
        alias allocator = Allocator.instance;

    } else {
        private Allocator allocator;

        /// No default construction if an allocator must be provided.
        this() @disable;

        /**
        * Use the given `allocator` for allocations.
        */
        this(Allocator allocator)
        in
        {
          assert(allocator !is null, "Allocator must not be null");
        }
        do
        {
          this.allocator = allocator;
        }
    }


    @property size_t length() const pure nothrow @nogc {
        //assert(used >= deleted);
        return used - deleted;
    }

    private Bucket[] allocHtable(scope const size_t sz) @nogc nothrow {
        Bucket[] _htable = allocator.makeArray!(Bucket)(sz);
        _htable[] = Bucket.init;
        return _htable;
    }

    private void initTableIfNeeded() @nogc nothrow {
        if(buckets is null){
            buckets = allocHtable(INIT_NUM_BUCKETS);
            firstUsed = cast(uint)INIT_NUM_BUCKETS;
        }

    }
    @property size_t dim() const pure nothrow @nogc {
        return buckets.length;
    }

    @property size_t mask() const pure nothrow @nogc {
        return dim - 1;
    }

    inout(Bucket)* findSlotInsert(const size_t hash) inout pure nothrow @nogc {
        for (size_t i = hash & mask, j = 1;; ++j){
            if (!buckets[i].filled)
                return &buckets[i];
            i = (i + j) & mask;
        }
    }

    inout(Bucket)* findSlotLookup(size_t hash, scope const K key) inout nothrow @nogc {
        for (size_t i = hash & mask, j = 1;; ++j){

            if (buckets[i].hash == hash && tkey.equals(key, buckets[i].entry.key)){
                return &buckets[i];
            }

            else if (buckets[i].empty)
                return null;
            i = (i + j) & mask;
        }
    }

    void set(scope const K key, scope const V val) @nogc nothrow {
        initTableIfNeeded();

        immutable keyHash = calcHash(key);

        if (auto p = findSlotLookup(keyHash, key)){
            p.entry.val = cast(V)val;
            return;
        }

        auto p = findSlotInsert(keyHash);

        if (p.deleted)
            --deleted;

        // check load factor and possibly grow
        else if (++used * GROW_DEN > dim * GROW_NUM){
            grow();
            p = findSlotInsert(keyHash);
            //assert(p.empty);
        }

        // update search cache and allocate entry
        firstUsed = min(firstUsed, cast(uint)(p - buckets.ptr));

        p.hash = keyHash;

        if(!p.deleted){
            Node* newNode = allocator.make!Node();
            newNode.key = key;
            newNode.val = cast(V)val;

            p.entry = newNode;
        }else{
            p.entry.key = key;
            p.entry.val = cast(V)val;
        }
    }

    private size_t calcHash(scope const K pkey) pure @nogc nothrow {
        // highest bit is set to distinguish empty/deleted from filled buckets
        immutable hash = tkey.getHash(pkey);
        return mix(hash) | HASH_FILLED_MARK;
    }

    void resize(const size_t sz) @nogc nothrow {
        auto obuckets = buckets;
        buckets = allocHtable(sz);

        foreach (ref b; obuckets[firstUsed .. $]){
            if (b.filled)
                *findSlotInsert(b.hash) = b;
            if (b.empty || b.deleted){
                allocator.dispose(b.entry);
                //core.stdc.stdlib.free(b.entry);
                b.entry = null;
            }

        }

        firstUsed = 0;
        used -= deleted;
        deleted = 0;

        //core.stdc.stdlib.free(obuckets.ptr);
        allocator.dispose(obuckets.ptr);
    }

    void rehash() @nogc nothrow {
        if (length)
            resize(nextpow2(INIT_DEN * length / INIT_NUM));
    }

    void grow() @nogc nothrow {
        if (length * SHRINK_DEN < GROW_FAC * dim * SHRINK_NUM)
            resize(dim);
        else
            resize(GROW_FAC * dim);
    }

    void shrink() @nogc nothrow {
        if (dim > INIT_NUM_BUCKETS)
            resize(dim / GROW_FAC);
    }

    bool remove(scope const K key) @nogc nothrow {
        if (!length)
            return false;

        immutable hash = calcHash(key);
        if (auto p = findSlotLookup(hash, key)){
            // clear entry
            p.hash = HASH_DELETED;
            //core.stdc.stdlib.free(p.entry);
            //p.entry = null;

            ++deleted;
            if (length * SHRINK_DEN < dim * SHRINK_NUM)
                shrink();

            return true;
        }
        return false;
    }

    V get(scope const K key) @nogc nothrow {
        return opIndex(key);
    }

    V opIndex(scope const K key) @nogc nothrow {
        if(auto ret = opBinaryRight!"in"(key))
            return *ret;
        return V.init;
    }

    void opIndexAssign(scope const V value, scope const K key) @nogc nothrow {
        set(key, value);
    }

    V* opBinaryRight(string op)(scope const K key) @nogc nothrow {
        static if (op == "in"){
            if (!length)
                return null;

            immutable keyHash = calcHash(key);
            if (auto buck = findSlotLookup(keyHash, key))
                return &buck.entry.val;
            return null;
        } else
        static assert(0, "Operator "~op~" not implemented");
    }

    /// returning slice must be deallocated like free(keys.ptr);
    K[] keys() @nogc nothrow {
        K[] ks = allocator.makeArray!K(length);
        //(cast(K*)malloc(length * K.sizeof))[0..length];
        size_t j;
        foreach (ref b; buckets[firstUsed .. $]){
            if (!b.filled){
                continue;
            }
            ks[j++] = b.entry.key;
        }

        return ks;
    }

    /// returning slice must be deallocated like free(values.ptr);
    V[] values() @nogc nothrow {
        V[] vals = allocator.makeArray!V(length);
        //(cast(V*)malloc(length * V.sizeof))[0..length];
        size_t j;
        foreach (ref b; buckets[firstUsed .. $]){
            if (!b.filled){
                continue;
            }
            vals[j++] = b.entry.val;
        }

        return vals;
    }

    void clear() @nogc nothrow { // WIP
        /+ not sure if this works with this port
        import core.stdc.string : memset;
        // clear all data, but don't change bucket array length
        memset(&buckets[firstUsed], 0, (buckets.length - firstUsed) * Bucket.sizeof);
        +/
        // just loop over entire slice
        foreach(ref b; buckets)
            if(b.entry !is null){
                //core.stdc.stdlib.free(b.entry);
                allocator.dispose(b.entry);
                b.entry = null;
            }
        deleted = used = 0;
        firstUsed = cast(uint) dim;
        buckets[] = Bucket.init;
    }

    void free() @nogc nothrow {
        foreach(ref b; buckets)
            if(b.entry !is null){
                //core.stdc.stdlib.free(b.entry);
                allocator.dispose(b.entry);
                b.entry = null;
            }

        //core.stdc.stdlib.free(buckets.ptr);
        allocator.dispose(buckets);
        deleted = used = 0;
        buckets = null;
    }

    Bcaa!(K, V) copy() @nogc nothrow {
        auto new_buckets = allocator.makeArray!Bucket(buckets.length);
        //cast(Bucket*)malloc(buckets.length * Bucket.sizeof);
        memcpy(new_buckets.ptr, buckets.ptr, buckets.length * Bucket.sizeof);
        Bcaa!(K, V) newAA;
        newAA.buckets = new_buckets[0..buckets.length];
        newAA.firstUsed = firstUsed;
        newAA.used = used;
        newAA.deleted = deleted;
        return newAA;
    }

    int opApply(int delegate(AAPair!(K, V)) @nogc nothrow dg) nothrow @nogc {
        int result = 0;
        if (buckets is null || buckets.length == 0)
            return 0;
        foreach (ref b; buckets[firstUsed .. $]){
            if (!b.filled)
                continue;
            result = dg(AAPair!(K, V)(&b.entry.key, &b.entry.val));
            if (result) {
                break;
            }
        }
        return 0;
    }

    // for GC usages
    int opApply(int delegate(AAPair!(K, V)) dg) {
        int result = 0;
        if (buckets is null || buckets.length == 0)
            return 0;
        foreach (ref b; buckets[firstUsed .. $]){
            if (!b.filled)
                continue;
            result = dg(AAPair!(K, V)(&b.entry.key, &b.entry.val));
            if (result) {
                break;
            }
        }
        return 0;
    }
    // TODO: .byKey(), .byValue(), .byKeyValue() ???
}

struct AAPair(K, V) {
    K* keyp;
    V* valp;
}

private size_t nextpow2(scope const size_t n) pure nothrow @nogc {
    import core.bitop : bsr;

    if (!n)
        return 1;

    const isPowerOf2 = !((n - 1) & n);
    return 1 << (bsr(n) + !isPowerOf2);
}

private size_t mix(size_t h) @safe pure nothrow @nogc {
    enum m = 0x5bd1e995;
    h ^= h >> 13;
    h *= m;
    h ^= h >> 15;
    return h;
}

private T min(T)(scope const T a, scope const T b) pure nothrow @nogc {
    return a < b ? a : b;
}

private T max(T)(scope const T a, scope const T b) pure nothrow @nogc {
    return b < a ? a : b;
}

@nogc unittest {
    import core.stdc.stdio;
    import core.stdc.time;

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
        //core.stdc.stdlib.free(keys.ptr);

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
}

// Test "in" works for AA without allocated storage.
@nogc unittest {
    Bcaa!(int, int) emptyMap;
    assert(0 !in emptyMap);

}

// Try to force a memory leak - issue #5
@nogc unittest {
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

    import core.stdc.stdio;
    printf(".x=%d .y%d %s\n", aas[100].x, aas[100].y, aas[100].txt.ptr);

    for(int i = 1024; i < 2048; i++) {
        aas.remove(i);
    }
}

