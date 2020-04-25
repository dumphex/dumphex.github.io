---
title: 多线程访问共享资源
date: 2020-04-25 15:07:28
tags:
- 多线程
- volatile
- mutex
- atomic
categories: C/C++
---

并发编程中, 当多线程访问共享资源时, 会产生竞争条件(race condition). 

<!-- more -->

## 1. 测试 
Base作为抽象基类, 提供bench()测试接口: 启动两个线程, 一个线程对共享资源m_var执行加一操作, 另一个线程对m_var执行减一操作. 正常情况下, 最后m_var预期结果应为0

```cpp
class Base {
 public:
  Base() {}
  virtual ~Base() {}

  virtual void iplus(int count) = 0;
  virtual void iminus(int count) = 0;

  void bench() {
     ScopedTiming st;
     int count = 1000000;
     std::thread t1(&Base::iplus, this, count);
     std::thread t2(&Base::iminus, this, count);
     t1.join();
     t2.join();
  }
};
```

Base基类派生出4个派生类, 对应4种不同的实现方案
- Derived: 对共享资源不加任何保护
- DerivedVolatile: 对共享资源添加volatile关键字修饰
- DerivedMutex: 对共享资源添加std::mutex互斥访问
- DerivedAtomic: 将共享资源设置为原子类型

```
graph BT
A[Base]
B1[Derived] --> A
B2[DerivedVolatile] --> A
B3[DerivedMutex]  --> A
B4[DerivedAtomic] --> A
```

### 1.1 测试环境
- Linux ubuntu18arm64 4.15.0-76-generic #86-Ubuntu SMP Fri Jan 17 17:25:58 UTC 2020 aarch64 aarch64 aarch64 GNU/Linux
- gcc version 7.4.0 (Ubuntu/Linaro 7.4.0-1ubuntu1~18.04.1)
- C++11

### 1.2 测试结果    

**Debug版本**
```
$ ./out/bin/atomic 
Derived : m_var = 0
ScopedTiming took 28 ms
~Derived : m_var = -90581

DerivedVolatile : m_var = 0
ScopedTiming took 27 ms
~DerivedVolatile : m_var = 559126

DerivedMutex : m_var = 0
ScopedTiming took 8748 ms
~DerivedMutex : m_var = 0

DerivedAtomic : m_var = 0
ScopedTiming took 190 ms
~DerivedAtomic : m_var = 0
```

**Release版本**
```
$ ./out/bin/atomic 
Derived : m_var = 0
ScopedTiming took 5 ms
~Derived : m_var = 0

DerivedVolatile : m_var = 0
ScopedTiming took 15 ms
~DerivedVolatile : m_var = 380629

DerivedMutex : m_var = 0
ScopedTiming took 1922 ms
~DerivedMutex : m_var = 0

DerivedAtomic : m_var = 0
ScopedTiming took 192 ms
~DerivedAtomic : m_var = 0

```

## 2. 实现方案
### 2.1 不加保护
测试代码
```cpp
class Derived : public Base {
 public:
  Derived() : m_var(0) {
    std::cout << __FUNCTION__ << " : m_var = " << m_var << std::endl;
  }

  ~Derived() {
    std::cout << __FUNCTION__ << " : m_var = " << m_var << std::endl << std::endl;
  }

  void iplus(int count) {
    while (count--) {
      m_var++;
    }
  }

  void iminus(int count) {
    while (count--) {
      m_var--;
    }
  }

 private:
  int m_var;
};
```

Release版本的汇编代码如下
```
00000000000027d8 <_ZN7Derived5iplusEi>:
    27d8:       34000081        cbz     w1, 27e8 <_ZN7Derived5iplusEi+0x10>
    27dc:       b9400802        ldr     w2, [x0, #8]
    27e0:       0b020021        add     w1, w1, w2
    27e4:       b9000801        str     w1, [x0, #8]
    27e8:       d65f03c0        ret
    27ec:       00000000        .inst   0x00000000 ; undefined

00000000000027f0 <_ZN7Derived6iminusEi>:
    27f0:       34000081        cbz     w1, 2800 <_ZN7Derived6iminusEi+0x10>
    27f4:       b9400802        ldr     w2, [x0, #8]
    27f8:       4b010041        sub     w1, w2, w1
    27fc:       b9000801        str     w1, [x0, #8]
    2800:       d65f03c0        ret
    2804:       00000000        .inst   0x00000000 ; undefined
```

从两个函数的汇编代码来看
- 由于iplus()/iminus()逻辑简单, 编译器在Release版本直接将while循环优化掉, 测试结果没有报错.
- 从Debug版本测试结果来看, 多线程访问共享资源是有问题的.

### 2.2 volatile
该版本中, 在共享资源m_var前添加volatile关键字进行修饰.

测试代码
```cpp
class DerivedVolatile : public Base {
 public:
  DerivedVolatile() : m_var(0) {
    std::cout << __FUNCTION__ << " : m_var = " << m_var << std::endl;
  }

  ~DerivedVolatile() {
    std::cout << __FUNCTION__ << " : m_var = " << m_var << std::endl << std::endl;
  }

  void iplus(int count) {
    while (count--) {
      m_var++;
    }
  }

  void iminus(int count) {
    while (count--) {
      m_var--;
    }
  }

 private:
  volatile int m_var;
};
```

反汇编如下
```asm
0000000000002808 <_ZN15DerivedVolatile5iplusEi>:
    2808:       51000422        sub     w2, w1, #0x1 
    280c:       340000e1        cbz     w1, 2828 <_ZN15DerivedVolatile5iplusEi+0x20>
    2810:       b9400801        ldr     w1, [x0, #8]
    2814:       51000442        sub     w2, w2, #0x1 
    2818:       3100045f        cmn     w2, #0x1 
    281c:       11000421        add     w1, w1, #0x1 
    2820:       b9000801        str     w1, [x0, #8]
    2824:       54ffff61        b.ne    2810 <_ZN15DerivedVolatile5iplusEi+0x8>  // b.any
    2828:       d65f03c0        ret
    282c:       00000000        .inst   0x00000000 ; undefined

0000000000002830 <_ZN15DerivedVolatile6iminusEi>:
    2830:       51000422        sub     w2, w1, #0x1
    2834:       340000e1        cbz     w1, 2850 <_ZN15DerivedVolatile6iminusEi+0x20>
    2838:       b9400801        ldr     w1, [x0, #8]
    283c:       51000442        sub     w2, w2, #0x1
    2840:       3100045f        cmn     w2, #0x1
    2844:       51000421        sub     w1, w1, #0x1
    2848:       b9000801        str     w1, [x0, #8]
    284c:       54ffff61        b.ne    2838 <_ZN15DerivedVolatile6iminusEi+0x8>  // b.any
    2850:       d65f03c0        ret
    2854:       00000000        .inst   0x00000000 ; undefined
```

从两个函数的汇编代码来看
- 加了volatile关键字后, 编译器没有再进行激进的优化, 而是按照程序正常流程进行编译.
- Debug/Release版本测试结果都显示多线程计算结果错误
- **volatile只能防止编译器做优化, 不能保证原子性**.

### 2.3 std::mutex
该版本中, 对共享资源m_var添加std::mutex互斥访问.

测试代码
```cpp
class DerivedMutex : public Base {
 public:
  DerivedMutex() : m_var(0) {
    std::cout << __FUNCTION__ << " : m_var = " << m_var << std::endl;
  }

  ~DerivedMutex() {
    std::cout << __FUNCTION__ << " : m_var = " << m_var << std::endl << std::endl;
  }

  void iplus(int count) {
    while (count--) {
      std::lock_guard<std::mutex> lck(m_mtx);
      m_var++;
    }
  }

  void iminus(int count) {
    while (count--) {
      std::lock_guard<std::mutex> lck(m_mtx);
      m_var--;
    }
  }

 private:
  std::mutex m_mtx;
  int m_var;
};
```

反汇编如下
```asm
0000000000002880 <_ZN12DerivedMutex6iminusEi>:
    2880:       a9bd7bfd        stp     x29, x30, [sp, #-48]!
    2884:       d0000082        adrp    x2, 14000 <__FRAME_END__+0x10300>
    2888:       910003fd        mov     x29, sp
    288c:       f947d042        ldr     x2, [x2, #4000]
    2890:       f9000ff4        str     x20, [sp, #24]
    2894:       aa0003f4        mov     x20, x0
    2898:       b4000302        cbz     x2, 28f8 <_ZN12DerivedMutex6iminusEi+0x78>
    289c:       f9000bb3        str     x19, [x29, #16]
    28a0:       2a0103f3        mov     w19, w1
    28a4:       f90013b5        str     x21, [x29, #32]
    28a8:       91002015        add     x21, x0, #0x8
    28ac:       34000173        cbz     w19, 28d8 <_ZN12DerivedMutex6iminusEi+0x58>
    28b0:       aa1503e0        mov     x0, x21
    28b4:       51000673        sub     w19, w19, #0x1
    28b8:       97fffe26        bl      2150 <pthread_mutex_lock@plt>
    28bc:       350002a0        cbnz    w0, 2910 <_ZN12DerivedMutex6iminusEi+0x90>
    28c0:       b9403a81        ldr     w1, [x20, #56]
    28c4:       aa1503e0        mov     x0, x21
    28c8:       51000421        sub     w1, w1, #0x1
    28cc:       b9003a81        str     w1, [x20, #56]
    28d0:       97fffe30        bl      2190 <pthread_mutex_unlock@plt>
    28d4:       35fffef3        cbnz    w19, 28b0 <_ZN12DerivedMutex6iminusEi+0x30>
    28d8:       f9400bb3        ldr     x19, [x29, #16]
    28dc:       f94013b5        ldr     x21, [x29, #32]
    28e0:       f9400ff4        ldr     x20, [sp, #24]
    28e4:       a8c37bfd        ldp     x29, x30, [sp], #48
    28e8:       d65f03c0        ret
    28ec:       b9403a80        ldr     w0, [x20, #56]
    28f0:       51000400        sub     w0, w0, #0x1
    28f4:       b9003a80        str     w0, [x20, #56]
    28f8:       51000421        sub     w1, w1, #0x1
    28fc:       3100043f        cmn     w1, #0x1
    2900:       54ffff61        b.ne    28ec <_ZN12DerivedMutex6iminusEi+0x6c>  // b.any
    2904:       f9400ff4        ldr     x20, [sp, #24]
    2908:       a8c37bfd        ldp     x29, x30, [sp], #48
    290c:       d65f03c0        ret
    2910:       97fffe28        bl      21b0 <_ZSt20__throw_system_errori@plt>
    2914:       00000000        .inst   0x00000000 ; undefined

00000000000029b8 <_ZN12DerivedMutex5iplusEi>:
    29b8:       a9bd7bfd        stp     x29, x30, [sp, #-48]!
    29bc:       d0000082        adrp    x2, 14000 <__FRAME_END__+0x10300>
    29c0:       910003fd        mov     x29, sp
    29c4:       f947d042        ldr     x2, [x2, #4000]
    29c8:       f9000ff4        str     x20, [sp, #24]
    29cc:       aa0003f4        mov     x20, x0
    29d0:       b4000302        cbz     x2, 2a30 <_ZN12DerivedMutex5iplusEi+0x78>
    29d4:       f9000bb3        str     x19, [x29, #16]
    29d8:       2a0103f3        mov     w19, w1
    29dc:       f90013b5        str     x21, [x29, #32]
    29e0:       91002015        add     x21, x0, #0x8
    29e4:       34000173        cbz     w19, 2a10 <_ZN12DerivedMutex5iplusEi+0x58>
    29e8:       aa1503e0        mov     x0, x21
    29ec:       51000673        sub     w19, w19, #0x1
    29f0:       97fffdd8        bl      2150 <pthread_mutex_lock@plt>
    29f4:       350002a0        cbnz    w0, 2a48 <_ZN12DerivedMutex5iplusEi+0x90>
    29f8:       b9403a81        ldr     w1, [x20, #56]
    29fc:       aa1503e0        mov     x0, x21
    2a00:       11000421        add     w1, w1, #0x1
    2a04:       b9003a81        str     w1, [x20, #56]
    2a08:       97fffde2        bl      2190 <pthread_mutex_unlock@plt>
    2a0c:       35fffef3        cbnz    w19, 29e8 <_ZN12DerivedMutex5iplusEi+0x30>
    2a10:       f9400bb3        ldr     x19, [x29, #16]
    2a14:       f94013b5        ldr     x21, [x29, #32]
    2a18:       f9400ff4        ldr     x20, [sp, #24]
    2a1c:       a8c37bfd        ldp     x29, x30, [sp], #48
    2a20:       d65f03c0        ret
    2a24:       b9403a80        ldr     w0, [x20, #56]
    2a28:       11000400        add     w0, w0, #0x1
    2a2c:       b9003a80        str     w0, [x20, #56]
    2a30:       51000421        sub     w1, w1, #0x1
    2a34:       3100043f        cmn     w1, #0x1
    2a38:       54ffff61        b.ne    2a24 <_ZN12DerivedMutex5iplusEi+0x6c>  // b.any
    2a3c:       f9400ff4        ldr     x20, [sp, #24]
    2a40:       a8c37bfd        ldp     x29, x30, [sp], #48
    2a44:       d65f03c0        ret
    2a48:       97fffdda        bl      21b0 <_ZSt20__throw_system_errori@plt>
    2a4c:       00000000        .inst   0x00000000 ; undefined
```

从两个函数的汇编代码来看
- std::mutex对m_var互斥访问, 底层调用pthread_mutex_lock()/pthread_mutex_unlock()来实现.
- Debug/Release版本测试结果显示多线程计算结果符合预期

### 2.4 std::atomic
该版本, 直接将共享资源int m_var改为原子类型std::atomic<int> m_var.

测试代码
```cpp
#define SEQ_CST
class DerivedAtomic : public Base {
 public:
  DerivedAtomic() : m_var(0) {
    std::cout << __FUNCTION__ << " : m_var = " << m_var << std::endl;
  }

  ~DerivedAtomic() {
    std::cout << __FUNCTION__ << " : m_var = " << m_var << std::endl << std::endl;
  }

  void iplus(int count) {
    while (count--) {
#ifdef SEQ_CST
      m_var++;
#else
      m_var.fetch_add(1, std::memory_order_relaxed);
#endif
    }
  }

  void iminus(int count) {
    while (count--) {
#ifdef SEQ_CST
      m_var--;
#else
      m_var.fetch_sub(1, std::memory_order_relaxed);
#endif
    }
  }

 private:
  std::atomic<int> m_var;
};
```

反汇编如下
```asm
0000000000002918 <_ZN13DerivedAtomic6iminusEi>:
    2918:       51000422        sub     w2, w1, #0x1
    291c:       34000141        cbz     w1, 2944 <_ZN13DerivedAtomic6iminusEi+0x2c>
    2920:       91002000        add     x0, x0, #0x8
    2924:       d503201f        nop
    2928:       885ffc01        ldaxr   w1, [x0]
    292c:       51000421        sub     w1, w1, #0x1
    2930:       8803fc01        stlxr   w3, w1, [x0]
    2934:       35ffffa3        cbnz    w3, 2928 <_ZN13DerivedAtomic6iminusEi+0x10>
    2938:       51000442        sub     w2, w2, #0x1
    293c:       3100045f        cmn     w2, #0x1
    2940:       54ffff41        b.ne    2928 <_ZN13DerivedAtomic6iminusEi+0x10>  // b.any
    2944:       d65f03c0        ret

0000000000002948 <_ZN13DerivedAtomic5iplusEi>:
    2948:       51000422        sub     w2, w1, #0x1
    294c:       34000141        cbz     w1, 2974 <_ZN13DerivedAtomic5iplusEi+0x2c>
    2950:       91002000        add     x0, x0, #0x8
    2954:       d503201f        nop
    2958:       885ffc01        ldaxr   w1, [x0]
    295c:       11000421        add     w1, w1, #0x1
    2960:       8803fc01        stlxr   w3, w1, [x0]
    2964:       35ffffa3        cbnz    w3, 2958 <_ZN13DerivedAtomic5iplusEi+0x10>
    2968:       51000442        sub     w2, w2, #0x1
    296c:       3100045f        cmn     w2, #0x1
    2970:       54ffff41        b.ne    2958 <_ZN13DerivedAtomic5iplusEi+0x10>  // b.any
    2974:       d65f03c0        ret
```

从两个函数的汇编代码来看
- 以iplus()函数为例, 
m_var++操作, 对应RMW(Read-Modify-Write), ARM硬件平台默认(顺序一致性内存模型)使用ldaxr/stlxr原子指令保证原子操作, 这里写回的实现有点类似spinlock
- Debug/Release版本测试结果显示多线程计算结果符合预期


## 3. 总结
|实现方案|正确性|说明|
|--------|------|----|
|不加保护|无法保证程序的正确性|多线程访问共享资源会产生竞争条件|
|volatile|无法保证程序的正确性|volatile只能防止编译器进行优化, 无法保证原子性|
|std::mutex|能保证程序的正确性|锁的粒度大, 影响性能|
|std::atomic|能保证程序的正确性|性能较好|

---

![程序员自我修养](http://ww1.sinaimg.cn/large/005Kyrj9ly1gbvsonijdoj3076076wex.jpg)

<center>
程序员自我修养(ID: dumphex)
</center>

---
