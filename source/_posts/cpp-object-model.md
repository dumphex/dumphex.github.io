---
title: 探索C++对象模型
date: 2020-03-27 10:29:01
tags:
- object model
- vptr
- vtable
- thunk
- virtual inheritance

categories: C/C++
---

本文分析了在不同场景下的C++对象模型

<!-- more -->

## 1. 前言

### 1.1 测试环境
- Linux ubuntu18arm64 4.15.0-76-generic #86-Ubuntu SMP Fri Jan 17 17:25:58 UTC 2020 aarch64 aarch64 aarch64 GNU/Linux
- gcc version 7.4.0 (Ubuntu/Linaro 7.4.0-1ubuntu1~18.04.1)
- glibc 2.27
- C++11


### 1.2 测试代码
```cpp
class Base {
 public:
  Base(): m_base(1) {}

  virtual ~Base() {
    m_base = 0;
  }

  virtual void foo() {
    m_base++;
  }

  virtual void bar() {
    m_base--;
  }


 private:
  int m_base;
};

class Base1 : public Base {
 public:
  Base1(): m_base1(21) {}

  virtual ~Base1() {
    m_base1 = 0;
  }

  virtual void foo() {
    m_base1++;
  }

 private:
  int m_base1;
};

class Base2 : virtual public Base {
 public:
  Base2(): m_base2(22) {}

  virtual ~Base2() {
    m_base2 = 0;
  }

  virtual void foo() {
   m_base2++;
  }

 private:
  int m_base2;
};


class Base3 : virtual public Base {
 public:
  Base3(): m_base3(23) {}

  virtual ~Base3() {
    m_base3 = 0;
  }

  virtual void foo() {
   m_base3++;
  }

 private:
  int m_base3;
};

class Derived : public Base2, public Base3 {
 public:
  Derived(): m_derived(3) {}

  virtual ~Derived() {
    m_derived = 0;
  }

  virtual void foo() {
    m_derived++;
  }

 private:
  int m_derived;
};

int main(int argc, char *argv[]) {

  Base b, *pb = nullptr;
  Base1 b1;
  Base2 b2;
  Base3 b3;
  Derived d;

  // Base and foo
  b.foo();
  pb = &b;
  pb->foo();

  // single inheritance
  b1.foo();
  b1.bar();
  pb = &b1;
  pb->foo();
  pb->bar();

  // virtual single inheritance
  pb = &b2;
  pb->foo();

  pb = &b3;
  pb->foo();

  // virtual multiple inheritance
  b2.foo();
  Base2 *pb2 = &d;
  pb2->foo();

  b3.foo();
  Base3 *pb3 = &d;
  pb3->foo();

  pb = &d;
  pb->foo();

  d.foo();
  d.bar();

  return 0;
}
```

各类的继承关系图如下

![base.jpeg](http://ww1.sinaimg.cn/large/005Kyrj9ly1gcslxg2n3tj30f30c4glo.jpg)

## 2. 调试分析

### 2.1 普通类 
普通类可以有虚函数, 也可以没有. 这里以带虚函数的Base b对象为例

#### 2.1.1 内存分析
**查看对象信息**
```asm
(gdb) p /x &b
$2 = 0xfffffffff218

(gdb) p sizeof(b)
$3 = 16

(gdb) x/2xg 0xfffffffff218
0xfffffffff218:	0x0000aaaaaaabcc58	0x0000aaaa00000001
```

**查看_vptr.Base**
```asm
(gdb) x/8xg 0x0000aaaaaaabcc58
0xaaaaaaabcc58 <_ZTV4Base+16>:	0x0000aaaaaaaab55c	0x0000aaaaaaaab588
0xaaaaaaabcc68 <_ZTV4Base+32>:	0x0000aaaaaaaab5ac	0x0000aaaaaaaab5d4
0xaaaaaaabcc78 <_ZTI7Derived>:	0x0000fffff7fc4338	0x0000aaaaaaaabcd0
0xaaaaaaabcc88 <_ZTI7Derived+16>:	0x0000000200000002	0x0000aaaaaaabccd8

(gdb) disas 0x0000aaaaaaaab55c
Dump of assembler code for function Base::~Base():
   0x0000aaaaaaaab55c <+0>:	sub	sp, sp, #0x10
   0x0000aaaaaaaab560 <+4>:	str	x0, [sp, #8]
   0x0000aaaaaaaab564 <+8>:	adrp	x0, 0xaaaaaaabc000
   0x0000aaaaaaaab568 <+12>:	add	x1, x0, #0xc58
   0x0000aaaaaaaab56c <+16>:	ldr	x0, [sp, #8]
   0x0000aaaaaaaab570 <+20>:	str	x1, [x0]
   0x0000aaaaaaaab574 <+24>:	ldr	x0, [sp, #8]
   0x0000aaaaaaaab578 <+28>:	str	wzr, [x0, #8]
   0x0000aaaaaaaab57c <+32>:	nop
   0x0000aaaaaaaab580 <+36>:	add	sp, sp, #0x10
   0x0000aaaaaaaab584 <+40>:	ret
End of assembler dump.

(gdb) disas 0x0000aaaaaaaab588
Dump of assembler code for function Base::~Base():
   0x0000aaaaaaaab588 <+0>:	stp	x29, x30, [sp, #-32]!
   0x0000aaaaaaaab58c <+4>:	mov	x29, sp
   0x0000aaaaaaaab590 <+8>:	str	x0, [x29, #24]
   0x0000aaaaaaaab594 <+12>:	ldr	x0, [x29, #24]
   0x0000aaaaaaaab598 <+16>:	bl	0xaaaaaaaab55c <Base::~Base()>
   0x0000aaaaaaaab59c <+20>:	ldr	x0, [x29, #24]
   0x0000aaaaaaaab5a0 <+24>:	bl	0xaaaaaaaab110 <_ZdlPv@plt>
   0x0000aaaaaaaab5a4 <+28>:	ldp	x29, x30, [sp], #32
   0x0000aaaaaaaab5a8 <+32>:	ret
End of assembler dump.

(gdb) disas 0x0000aaaaaaaab5ac
Dump of assembler code for function Base::foo():
   0x0000aaaaaaaab5ac <+0>:	sub	sp, sp, #0x10
   0x0000aaaaaaaab5b0 <+4>:	str	x0, [sp, #8]
   0x0000aaaaaaaab5b4 <+8>:	ldr	x0, [sp, #8]
   0x0000aaaaaaaab5b8 <+12>:	ldr	w0, [x0, #8]
   0x0000aaaaaaaab5bc <+16>:	add	w1, w0, #0x1
   0x0000aaaaaaaab5c0 <+20>:	ldr	x0, [sp, #8]
   0x0000aaaaaaaab5c4 <+24>:	str	w1, [x0, #8]
   0x0000aaaaaaaab5c8 <+28>:	nop
   0x0000aaaaaaaab5cc <+32>:	add	sp, sp, #0x10
   0x0000aaaaaaaab5d0 <+36>:	ret
End of assembler dump.

(gdb) disas 0x0000aaaaaaaab5d4
Dump of assembler code for function Base::bar():
   0x0000aaaaaaaab5d4 <+0>:	sub	sp, sp, #0x10
   0x0000aaaaaaaab5d8 <+4>:	str	x0, [sp, #8]
   0x0000aaaaaaaab5dc <+8>:	ldr	x0, [sp, #8]
   0x0000aaaaaaaab5e0 <+12>:	ldr	w0, [x0, #8]
   0x0000aaaaaaaab5e4 <+16>:	sub	w1, w0, #0x1
   0x0000aaaaaaaab5e8 <+20>:	ldr	x0, [sp, #8]
   0x0000aaaaaaaab5ec <+24>:	str	w1, [x0, #8]
   0x0000aaaaaaaab5f0 <+28>:	nop
   0x0000aaaaaaaab5f4 <+32>:	add	sp, sp, #0x10
   0x0000aaaaaaaab5f8 <+36>:	ret
End of assembler dump.
```

#### 2.1.2 对象模型
根据前面的分析， 对Base类(包含虚函数)的实例b， 其对象模型如下
```
+-----------+            
|_vptr.Base |   ---->    +-------------+ 
+-----------+            |Base::~Base()|
|  m_base   |            +-------------+ 
+-----------+            |Base::~Base()|
                         +-------------+
                         | Base::foo() |
                         +-------------+
                         | Base::bar() |
                         +-------------+                         
```

这里vtable中有两个版本的Base::~Base()
- 第1个Base::~Base()完成Base类的析构函数功能. 以前提到的**栈对象**/**局部静态对象**/**全局对象**析构时会调用该版本
- 第2个Base::\~Base()先调用第1个Base::~Base()，然后释放对象占用的内存. **堆对象**析构时会调用该版本.

#### 2.1.3 代码分析

**通过实例直接调用虚函数**
```cpp
  b.foo();
```

反汇编如下
```asm
   0x0000aaaaaaaab2d8 <+84>:	add	x0, x29, #0x48
   0x0000aaaaaaaab2dc <+88>:	bl	0xaaaaaaaab5ac <Base::foo()>
```

**通过指针调用虚函数**
```cpp
  pb = &b;
  pb->foo();
```

反汇编如下
```asm
   0x0000aaaaaaaab2e0 <+92>:	add	x0, x29, #0x48
   0x0000aaaaaaaab2e4 <+96>:	str	x0, [x29, #48]
   0x0000aaaaaaaab2e8 <+100>:	ldr	x0, [x29, #48]
   
   0x0000aaaaaaaab2ec <+104>:	ldr	x0, [x0]
   
   0x0000aaaaaaaab2f0 <+108>:	add	x0, x0, #0x10
   0x0000aaaaaaaab2f4 <+112>:	ldr	x1, [x0]
   
   0x0000aaaaaaaab2f8 <+116>:	ldr	x0, [x29, #48]
   0x0000aaaaaaaab2fc <+120>:	blr	x1
```

流程如下
- 确定当前对象地址(x0 = x29 + 0x48)
- 找到vptr(gcc下默认就是[x0])
- 在vtable中找到要调用的虚函数(vtable[2])
- 跳转到虚函数执行

### 2.2 单一继承

这里以Base1 b1对象为例

#### 2.2.1 内存分析
**查看对象信息**
```asm
(gdb) p /x &b1
$4 = 0xfffffffff228

(gdb) p sizeof(b1)
$5 = 16

(gdb) x/2xg 0xfffffffff228
0xfffffffff228:	0x0000aaaaaaabcc28	0x0000001500000001
```

**查看_vptr.Base**
```asm
(gdb) x/8xg 0x0000aaaaaaabcc28
0xaaaaaaabcc28 <_ZTV5Base1+16>:	0x0000aaaaaaaab638	0x0000aaaaaaaab670
0xaaaaaaabcc38 <_ZTV5Base1+32>:	0x0000aaaaaaaab694	0x0000aaaaaaaab5d4
0xaaaaaaabcc48 <_ZTV4Base>:	0x0000000000000000	0x0000aaaaaaabcd18
0xaaaaaaabcc58 <_ZTV4Base+16>:	0x0000aaaaaaaab55c	0x0000aaaaaaaab588

(gdb) disas 0x0000aaaaaaaab638
Dump of assembler code for function Base1::~Base1():
   0x0000aaaaaaaab638 <+0>:	stp	x29, x30, [sp, #-32]!
   0x0000aaaaaaaab63c <+4>:	mov	x29, sp
   0x0000aaaaaaaab640 <+8>:	str	x0, [x29, #24]
   0x0000aaaaaaaab644 <+12>:	adrp	x0, 0xaaaaaaabc000
   0x0000aaaaaaaab648 <+16>:	add	x1, x0, #0xc28
   0x0000aaaaaaaab64c <+20>:	ldr	x0, [x29, #24]
   0x0000aaaaaaaab650 <+24>:	str	x1, [x0]
   0x0000aaaaaaaab654 <+28>:	ldr	x0, [x29, #24]
   0x0000aaaaaaaab658 <+32>:	str	wzr, [x0, #12]
   0x0000aaaaaaaab65c <+36>:	ldr	x0, [x29, #24]
   0x0000aaaaaaaab660 <+40>:	bl	0xaaaaaaaab55c <Base::~Base()>
   0x0000aaaaaaaab664 <+44>:	nop
   0x0000aaaaaaaab668 <+48>:	ldp	x29, x30, [sp], #32
   0x0000aaaaaaaab66c <+52>:	ret
End of assembler dump.

(gdb) disas 0x0000aaaaaaaab670
Dump of assembler code for function Base1::~Base1():
   0x0000aaaaaaaab670 <+0>:	stp	x29, x30, [sp, #-32]!
   0x0000aaaaaaaab674 <+4>:	mov	x29, sp
   0x0000aaaaaaaab678 <+8>:	str	x0, [x29, #24]
   0x0000aaaaaaaab67c <+12>:	ldr	x0, [x29, #24]
   0x0000aaaaaaaab680 <+16>:	bl	0xaaaaaaaab638 <Base1::~Base1()>
   0x0000aaaaaaaab684 <+20>:	ldr	x0, [x29, #24]
   0x0000aaaaaaaab688 <+24>:	bl	0xaaaaaaaab110 <_ZdlPv@plt>
   0x0000aaaaaaaab68c <+28>:	ldp	x29, x30, [sp], #32
   0x0000aaaaaaaab690 <+32>:	ret
End of assembler dump.

(gdb) disas 0x0000aaaaaaaab694
Dump of assembler code for function Base1::foo():
   0x0000aaaaaaaab694 <+0>:	sub	sp, sp, #0x10
   0x0000aaaaaaaab698 <+4>:	str	x0, [sp, #8]
   0x0000aaaaaaaab69c <+8>:	ldr	x0, [sp, #8]
   0x0000aaaaaaaab6a0 <+12>:	ldr	w0, [x0, #12]
   0x0000aaaaaaaab6a4 <+16>:	add	w1, w0, #0x1
   0x0000aaaaaaaab6a8 <+20>:	ldr	x0, [sp, #8]
   0x0000aaaaaaaab6ac <+24>:	str	w1, [x0, #12]
   0x0000aaaaaaaab6b0 <+28>:	nop
   0x0000aaaaaaaab6b4 <+32>:	add	sp, sp, #0x10
   0x0000aaaaaaaab6b8 <+36>:	ret
End of assembler dump.

(gdb) disas 0x0000aaaaaaaab5d4
Dump of assembler code for function Base::bar():
   0x0000aaaaaaaab5d4 <+0>:	sub	sp, sp, #0x10
   0x0000aaaaaaaab5d8 <+4>:	str	x0, [sp, #8]
   0x0000aaaaaaaab5dc <+8>:	ldr	x0, [sp, #8]
   0x0000aaaaaaaab5e0 <+12>:	ldr	w0, [x0, #8]
   0x0000aaaaaaaab5e4 <+16>:	sub	w1, w0, #0x1
   0x0000aaaaaaaab5e8 <+20>:	ldr	x0, [sp, #8]
   0x0000aaaaaaaab5ec <+24>:	str	w1, [x0, #8]
   0x0000aaaaaaaab5f0 <+28>:	nop
   0x0000aaaaaaaab5f4 <+32>:	add	sp, sp, #0x10
   0x0000aaaaaaaab5f8 <+36>:	ret
End of assembler dump.
```

#### 2.2.2 对象模型

根据前面的分析，对Base1类(包含虚函数 + 单一继承)的实例b1， 其对象模型如下

```
+-----------+            
|_vptr.Base |   ---->    +---------------+
+-----------+            |Base1::~Base1()|
|  m_base   |            +---------------+ 
+-----------+            |Base1::~Base1()|
|  m_base1  |            +---------------+
+-----------+            |  Base1::foo() |
                         +---------------+
                         |  Base::bar()  |
                         +---------------+                         
```

- 单一继承情况下, 虽然_vptr.Base包含基类名, 但实际是Base1类的vptr
- Base1 override基类Base的foo(), 但没有override基类Base的bar(), 所以Base1虚表中的foo()是Base1::foo(), bar()是Base::bar().

#### 2.2.3 代码分析

**通过实例直接调用虚函数**

```cpp
  b1.foo();
```

反汇编如下
```asm
   0x0000aaaaaaaab300 <+124>:	add	x0, x29, #0x58
   0x0000aaaaaaaab304 <+128>:	bl	0xaaaaaaaab694 <Base1::foo()>
```   
  
**通过基类指针调用虚函数**
```cpp
  pb = &b1;
  pb->foo();
```

反汇编如下
```asm
   0x0000aaaaaaaab310 <+140>:	add	x0, x29, #0x58
   0x0000aaaaaaaab314 <+144>:	str	x0, [x29, #48]
   0x0000aaaaaaaab318 <+148>:	ldr	x0, [x29, #48]
   
   0x0000aaaaaaaab31c <+152>:	ldr	x0, [x0]
   
   0x0000aaaaaaaab320 <+156>:	add	x0, x0, #0x10
   0x0000aaaaaaaab324 <+160>:	ldr	x1, [x0]
   
   0x0000aaaaaaaab328 <+164>:	ldr	x0, [x29, #48]
   0x0000aaaaaaaab32c <+168>:	blr	x1
```


### 2.3 虚继承1
先看虚继承简单的情形, 这里以Base2 b2对象为例

#### 2.3.1 内存分析
**查看对象信息**
```asm
(gdb) p /x &b2
$6 = 0xfffffffff238

(gdb) p sizeof(b2)
$7 = 32

(gdb) x/4xg 0xfffffffff238
0xfffffffff238:	0x0000aaaaaaabcba8	0x0000ffff00000016
0xfffffffff248:	0x0000aaaaaaabcbe8	0x0000ffff00000001
```

这里有两个vptr
- _vptr.Base2 = 0x0000aaaaaaabcba8
- _vptr.Base = 0x0000aaaaaaabcbe8

**查看_vptr.Base2**
```asm
(gdb) x/8xg 0x0000aaaaaaabcba8
0xaaaaaaabcba8 <_ZTV5Base2+24>:	0x0000aaaaaaaab7c4	0x0000aaaaaaaab824
0xaaaaaaabcbb8 <_ZTV5Base2+40>:	0x0000aaaaaaaab858	0x0000000000000000
0xaaaaaaabcbc8 <_ZTV5Base2+56>:	0xfffffffffffffff0	0xfffffffffffffff0
0xaaaaaaabcbd8 <_ZTV5Base2+72>:	0xfffffffffffffff0	0x0000aaaaaaabccd8

(gdb) disas 0x0000aaaaaaaab7c4
Dump of assembler code for function Base2::~Base2():
   0x0000aaaaaaaab7c4 <+0>:	stp	x29, x30, [sp, #-32]!
   0x0000aaaaaaaab7c8 <+4>:	mov	x29, sp
   0x0000aaaaaaaab7cc <+8>:	str	x0, [x29, #24]
   0x0000aaaaaaaab7d0 <+12>:	adrp	x0, 0xaaaaaaabc000
   0x0000aaaaaaaab7d4 <+16>:	add	x1, x0, #0xba8
   0x0000aaaaaaaab7d8 <+20>:	ldr	x0, [x29, #24]
   0x0000aaaaaaaab7dc <+24>:	str	x1, [x0]
   0x0000aaaaaaaab7e0 <+28>:	ldr	x0, [x29, #24]
   0x0000aaaaaaaab7e4 <+32>:	add	x0, x0, #0x10
   0x0000aaaaaaaab7e8 <+36>:	adrp	x1, 0xaaaaaaabc000
   0x0000aaaaaaaab7ec <+40>:	add	x1, x1, #0xbe8
   0x0000aaaaaaaab7f0 <+44>:	str	x1, [x0]
   0x0000aaaaaaaab7f4 <+48>:	ldr	x0, [x29, #24]
   0x0000aaaaaaaab7f8 <+52>:	str	wzr, [x0, #8]
   0x0000aaaaaaaab7fc <+56>:	ldr	x0, [x29, #24]
   0x0000aaaaaaaab800 <+60>:	add	x0, x0, #0x10
   0x0000aaaaaaaab804 <+64>:	bl	0xaaaaaaaab55c <Base::~Base()>
   0x0000aaaaaaaab808 <+68>:	nop
   0x0000aaaaaaaab80c <+72>:	ldp	x29, x30, [sp], #32
   0x0000aaaaaaaab810 <+76>:	ret
End of assembler dump.

(gdb) disas 0x0000aaaaaaaab824
Dump of assembler code for function Base2::~Base2():
   0x0000aaaaaaaab824 <+0>:	stp	x29, x30, [sp, #-32]!
   0x0000aaaaaaaab828 <+4>:	mov	x29, sp
   0x0000aaaaaaaab82c <+8>:	str	x0, [x29, #24]
   0x0000aaaaaaaab830 <+12>:	ldr	x0, [x29, #24]
   0x0000aaaaaaaab834 <+16>:	bl	0xaaaaaaaab7c4 <Base2::~Base2()>
   0x0000aaaaaaaab838 <+20>:	ldr	x0, [x29, #24]
   0x0000aaaaaaaab83c <+24>:	bl	0xaaaaaaaab110 <_ZdlPv@plt>
   0x0000aaaaaaaab840 <+28>:	ldp	x29, x30, [sp], #32
   0x0000aaaaaaaab844 <+32>:	ret
End of assembler dump.

(gdb) disas 0x0000aaaaaaaab858
Dump of assembler code for function Base2::foo():
   0x0000aaaaaaaab858 <+0>:	sub	sp, sp, #0x10
   0x0000aaaaaaaab85c <+4>:	str	x0, [sp, #8]
   0x0000aaaaaaaab860 <+8>:	ldr	x0, [sp, #8]
   0x0000aaaaaaaab864 <+12>:	ldr	w0, [x0, #8]
   0x0000aaaaaaaab868 <+16>:	add	w1, w0, #0x1
   0x0000aaaaaaaab86c <+20>:	ldr	x0, [sp, #8]
   0x0000aaaaaaaab870 <+24>:	str	w1, [x0, #8]
   0x0000aaaaaaaab874 <+28>:	nop
   0x0000aaaaaaaab878 <+32>:	add	sp, sp, #0x10
   0x0000aaaaaaaab87c <+36>:	ret
End of assembler dump.
```

**查看_vptr.Base**
```asm
(gdb) x/8xg 0x0000aaaaaaabcbe8
0xaaaaaaabcbe8 <_ZTV5Base2+88>:	0x0000aaaaaaaab814	0x0000aaaaaaaab848
0xaaaaaaabcbf8 <_ZTV5Base2+104>:	0x0000aaaaaaaab880	0x0000aaaaaaaab5d4
0xaaaaaaabcc08 <_ZTT5Base2>:	0x0000aaaaaaabcba8	0x0000aaaaaaabcbe8
0xaaaaaaabcc18 <_ZTV5Base1>:	0x0000000000000000	0x0000aaaaaaabcd00

(gdb) disas 0x0000aaaaaaaab814
Dump of assembler code for function _ZTv0_n24_N5Base2D1Ev:
   0x0000aaaaaaaab814 <+0>:	ldr	x16, [x0]
   0x0000aaaaaaaab818 <+4>:	ldur	x17, [x16, #-24]
   0x0000aaaaaaaab81c <+8>:	add	x0, x0, x17
   0x0000aaaaaaaab820 <+12>:	b	0xaaaaaaaab7c4 <Base2::~Base2()>
End of assembler dump.

(gdb) disas 0x0000aaaaaaaab848
Dump of assembler code for function _ZTv0_n24_N5Base2D0Ev:
   0x0000aaaaaaaab848 <+0>:	ldr	x16, [x0]
   0x0000aaaaaaaab84c <+4>:	ldur	x17, [x16, #-24]
   0x0000aaaaaaaab850 <+8>:	add	x0, x0, x17
   0x0000aaaaaaaab854 <+12>:	b	0xaaaaaaaab824 <Base2::~Base2()>
End of assembler dump.

(gdb) disas 0x0000aaaaaaaab880
Dump of assembler code for function _ZTv0_n32_N5Base23fooEv:
   0x0000aaaaaaaab880 <+0>:	ldr	x16, [x0]
   0x0000aaaaaaaab884 <+4>:	ldur	x17, [x16, #-32]
   0x0000aaaaaaaab888 <+8>:	add	x0, x0, x17
   0x0000aaaaaaaab88c <+12>:	b	0xaaaaaaaab858 <Base2::foo()>
End of assembler dump.

(gdb) disas 0x0000aaaaaaaab5d4
Dump of assembler code for function Base::bar():
   0x0000aaaaaaaab5d4 <+0>:	sub	sp, sp, #0x10
   0x0000aaaaaaaab5d8 <+4>:	str	x0, [sp, #8]
   0x0000aaaaaaaab5dc <+8>:	ldr	x0, [sp, #8]
   0x0000aaaaaaaab5e0 <+12>:	ldr	w0, [x0, #8]
   0x0000aaaaaaaab5e4 <+16>:	sub	w1, w0, #0x1
   0x0000aaaaaaaab5e8 <+20>:	ldr	x0, [sp, #8]
   0x0000aaaaaaaab5ec <+24>:	str	w1, [x0, #8]
   0x0000aaaaaaaab5f0 <+28>:	nop
   0x0000aaaaaaaab5f4 <+32>:	add	sp, sp, #0x10
   0x0000aaaaaaaab5f8 <+36>:	ret
End of assembler dump.
```

几点说明:
- 这里的_vptr.Base(0x0000aaaaaaabcbe8)并不是Base类真正的vptr(0x0000aaaaaaabcc58)
- 前面的三个函数是**编译器**生成的**thunk**函数，用于修正对象地址(this指针由Base子对象地址切换到Base2对象地址)，跳转到Base2 override的虚函数。
- 最后一个虚函数是Base::bar(), Base2没有override, 这里直接存储其地址, this指针为Base子对象地址

#### 2.3.2 对象模型
根据前面的分析，对Base2类(虚继承)的实例b2， 其对象模型如下

```
+-----------+            
|_vptr.Base2|   ---->    +---------------+
+-----------+            |Base2::~Base2()| <------------------
|  m_base2  |            +---------------+                   |
+-----------+            |Base2::~Base2()| <-----------------|--
|_vptr.Base |  ----|     +---------------+                   | |
+-----------+      |     |  Base2::foo() | <-----------------|-|--
|   m_base  |      |     +---------------+                   | | |
+-----------+      |                                         | | |
                   | --> +--------------------------------+  | | |
                         |virtual thunk to Base2::~Base2()|--- | |
                         +--------------------------------+    | |
                         |virtual thunk to Base2::~Base2()|----- |
                         +--------------------------------+      |
                         | virtual thunk to Base2::foo()  |-------
                         +--------------------------------+
                         |           Base::bar()          |
                         +--------------------------------+
```

#### 2.3.3 代码分析

**通过实例直接调用虚函数**
```cpp
b2.foo();
```

反汇编如下
```asm
   0x0000aaaaaaaab390 <+268>:	add	x0, x29, #0x68
   0x0000aaaaaaaab394 <+272>:	bl	0xaaaaaaaab858 <Base2::foo()>
```

**通过基类指针调用虚函数**
```cpp
  pb = &b2;
  pb->foo();
```

对应汇编如下:
```asm
   0x0000aaaaaaaab348 <+196>:	add	x0, x29, #0x68
   
   0x0000aaaaaaaab34c <+200>:	add	x0, x0, #0x10
   0x0000aaaaaaaab350 <+204>:	str	x0, [x29, #48]
   0x0000aaaaaaaab354 <+208>:	ldr	x0, [x29, #48]
   
   0x0000aaaaaaaab358 <+212>:	ldr	x0, [x0]
   
   0x0000aaaaaaaab35c <+216>:	add	x0, x0, #0x10
   0x0000aaaaaaaab360 <+220>:	ldr	x1, [x0]
   
   0x0000aaaaaaaab364 <+224>:	ldr	x0, [x29, #48]
   0x0000aaaaaaaab368 <+228>:	blr	x1
```

通过上面代码可以看到, 虚继承和单一继承在通过基类指针访问派生类对象过程中, 
流程不同.
- 派生类对象地址加上特定的偏移得到**基类子对象地址**(编译器在处理pb = &b2后, 此时的pb已经不是b2的地址了, 而是&b2 + 0x10, 指向Base子对象) 
- 根据基类子对象地址, 找到_vptr.Base
- 根据要调用的虚函数, 在vtable找到对应项: **thunk函数**或**基类版本**
- thunk函数是一段汇编代码, 通过修正对象地址(基类子对象地址切换到派生类对象地址), 最终跳转到派生类版本执行

### 2.4 虚继承2

最后看看虚继承最复杂的情形, 这里以Derived d对象为例

#### 2.4.1 内存分析
**查看对象信息**
```asm
(gdb) p /x &d
$10 = 0xfffffffff278

(gdb) p sizeof(d)
$11 = 48

(gdb) x/6xg 0xfffffffff278
0xfffffffff278:	0x0000aaaaaaabc950	0x0000aaaa00000016
0xfffffffff288:	0x0000aaaaaaabc980	0x0000000500000017
0xfffffffff298:	0x0000aaaaaaabc9c0	0x0000aaaa00000001
```

**查看_vptr.Base2**
```asm
(gdb) x/8xg 0x0000aaaaaaabc950
0xaaaaaaabc950 <_ZTV7Derived+24>:	0x0000aaaaaaaabafc	0x0000aaaaaaaabba8
0xaaaaaaabc960 <_ZTV7Derived+40>:	0x0000aaaaaaaabbe4	0x0000000000000010
0xaaaaaaabc970 <_ZTV7Derived+56>:	0xfffffffffffffff0	0x0000aaaaaaabcc78
0xaaaaaaabc980 <_ZTV7Derived+72>:	0x0000aaaaaaaabba0	0x0000aaaaaaaabbdc

(gdb) disas 0x0000aaaaaaaabafc
Dump of assembler code for function Derived::~Derived():
   0x0000aaaaaaaabafc <+0>:	stp	x29, x30, [sp, #-32]!
   0x0000aaaaaaaabb00 <+4>:	mov	x29, sp
   0x0000aaaaaaaabb04 <+8>:	str	x0, [x29, #24]
   0x0000aaaaaaaabb08 <+12>:	adrp	x0, 0xaaaaaaabc000
   0x0000aaaaaaaabb0c <+16>:	add	x1, x0, #0x950
   0x0000aaaaaaaabb10 <+20>:	ldr	x0, [x29, #24]
   0x0000aaaaaaaabb14 <+24>:	str	x1, [x0]
   0x0000aaaaaaaabb18 <+28>:	ldr	x0, [x29, #24]
   0x0000aaaaaaaabb1c <+32>:	add	x0, x0, #0x20
   0x0000aaaaaaaabb20 <+36>:	adrp	x1, 0xaaaaaaabc000
   0x0000aaaaaaaabb24 <+40>:	add	x1, x1, #0x9c0
   0x0000aaaaaaaabb28 <+44>:	str	x1, [x0]
   0x0000aaaaaaaabb2c <+48>:	adrp	x0, 0xaaaaaaabc000
   0x0000aaaaaaaabb30 <+52>:	add	x1, x0, #0x980
   0x0000aaaaaaaabb34 <+56>:	ldr	x0, [x29, #24]
   0x0000aaaaaaaabb38 <+60>:	str	x1, [x0, #16]
   0x0000aaaaaaaabb3c <+64>:	ldr	x0, [x29, #24]
   0x0000aaaaaaaabb40 <+68>:	str	wzr, [x0, #28]
   0x0000aaaaaaaabb44 <+72>:	ldr	x0, [x29, #24]
   0x0000aaaaaaaabb48 <+76>:	add	x2, x0, #0x10
   0x0000aaaaaaaabb4c <+80>:	adrp	x0, 0xaaaaaaabc000
   0x0000aaaaaaaabb50 <+84>:	add	x0, x0, #0x9f8
   0x0000aaaaaaaabb54 <+88>:	mov	x1, x0
   0x0000aaaaaaaabb58 <+92>:	mov	x0, x2
   0x0000aaaaaaaabb5c <+96>:	bl	0xaaaaaaaab940 <Base3::~Base3()>
   0x0000aaaaaaaabb60 <+100>:	ldr	x2, [x29, #24]
   0x0000aaaaaaaabb64 <+104>:	adrp	x0, 0xaaaaaaabc000
   0x0000aaaaaaaabb68 <+108>:	add	x0, x0, #0x9e8
   0x0000aaaaaaaabb6c <+112>:	mov	x1, x0
   0x0000aaaaaaaabb70 <+116>:	mov	x0, x2
   0x0000aaaaaaaabb74 <+120>:	bl	0xaaaaaaaab76c <Base2::~Base2()>
   0x0000aaaaaaaabb78 <+124>:	ldr	x0, [x29, #24]
   0x0000aaaaaaaabb7c <+128>:	add	x0, x0, #0x20
   0x0000aaaaaaaabb80 <+132>:	bl	0xaaaaaaaab55c <Base::~Base()>
   0x0000aaaaaaaabb84 <+136>:	nop
   0x0000aaaaaaaabb88 <+140>:	ldp	x29, x30, [sp], #32
   0x0000aaaaaaaabb8c <+144>:	ret
End of assembler dump.

(gdb) disas 0x0000aaaaaaaabba8
Dump of assembler code for function Derived::~Derived():
   0x0000aaaaaaaabba8 <+0>:	stp	x29, x30, [sp, #-32]!
   0x0000aaaaaaaabbac <+4>:	mov	x29, sp
   0x0000aaaaaaaabbb0 <+8>:	str	x0, [x29, #24]
   0x0000aaaaaaaabbb4 <+12>:	ldr	x0, [x29, #24]
   0x0000aaaaaaaabbb8 <+16>:	bl	0xaaaaaaaabafc <Derived::~Derived()>
   0x0000aaaaaaaabbbc <+20>:	ldr	x0, [x29, #24]
   0x0000aaaaaaaabbc0 <+24>:	bl	0xaaaaaaaab110 <_ZdlPv@plt>
   0x0000aaaaaaaabbc4 <+28>:	ldp	x29, x30, [sp], #32
   0x0000aaaaaaaabbc8 <+32>:	ret
End of assembler dump.

(gdb) disas 0x0000aaaaaaaabbe4
Dump of assembler code for function Derived::foo():
   0x0000aaaaaaaabbe4 <+0>:	sub	sp, sp, #0x10
   0x0000aaaaaaaabbe8 <+4>:	str	x0, [sp, #8]
=> 0x0000aaaaaaaabbec <+8>:	ldr	x0, [sp, #8]
   0x0000aaaaaaaabbf0 <+12>:	ldr	w0, [x0, #28]
   0x0000aaaaaaaabbf4 <+16>:	add	w1, w0, #0x1
   0x0000aaaaaaaabbf8 <+20>:	ldr	x0, [sp, #8]
   0x0000aaaaaaaabbfc <+24>:	str	w1, [x0, #28]
   0x0000aaaaaaaabc00 <+28>:	nop
   0x0000aaaaaaaabc04 <+32>:	add	sp, sp, #0x10
   0x0000aaaaaaaabc08 <+36>:	ret
End of assembler dump.
```

Base2类是Derived派生类列表的第一个直接基类, 这里的_vptr.Base2实际是Derived类的vptr

**查看_vptr.Base3**
```asm
(gdb) x/8xg 0x0000aaaaaaabc980
0xaaaaaaabc980 <_ZTV7Derived+72>:	0x0000aaaaaaaabba0	0x0000aaaaaaaabbdc
0xaaaaaaabc990 <_ZTV7Derived+88>:	0x0000aaaaaaaabc1c	0x0000000000000000
0xaaaaaaabc9a0 <_ZTV7Derived+104>:	0xffffffffffffffe0	0xffffffffffffffe0
0xaaaaaaabc9b0 <_ZTV7Derived+120>:	0xffffffffffffffe0	0x0000aaaaaaabcc78

(gdb) disas 0x0000aaaaaaaabba0
Dump of assembler code for function _ZThn16_N7DerivedD1Ev:
   0x0000aaaaaaaabba0 <+0>:	sub	x0, x0, #0x10
   0x0000aaaaaaaabba4 <+4>:	b	0xaaaaaaaabafc <Derived::~Derived()>
End of assembler dump.

(gdb) disas 0x0000aaaaaaaabbdc
Dump of assembler code for function _ZThn16_N7DerivedD0Ev:
   0x0000aaaaaaaabbdc <+0>:	sub	x0, x0, #0x10
   0x0000aaaaaaaabbe0 <+4>:	b	0xaaaaaaaabba8 <Derived::~Derived()>
End of assembler dump.

(gdb) disas 0x0000aaaaaaaabc1c
Dump of assembler code for function _ZThn16_N7Derived3fooEv:
   0x0000aaaaaaaabc1c <+0>:	sub	x0, x0, #0x10
   0x0000aaaaaaaabc20 <+4>:	b	0xaaaaaaaabbe4 <Derived::foo()>
End of assembler dump.
```

Base3类是Derived派生类列表的第二个直接基类, 这里的_vptr.Base3并不是Base3类的vptr.

**_vptr.Base**
```asm
(gdb) x/8xg 0x0000aaaaaaabc9c0
0xaaaaaaabc9c0 <_ZTV7Derived+136>:	0x0000aaaaaaaabb90	0x0000aaaaaaaabbcc
0xaaaaaaabc9d0 <_ZTV7Derived+152>:	0x0000aaaaaaaabc0c	0x0000aaaaaaaab5d4
0xaaaaaaabc9e0 <_ZTT7Derived>:	0x0000aaaaaaabc950	0x0000aaaaaaabca30
0xaaaaaaabc9f0 <_ZTT7Derived+16>:	0x0000aaaaaaabca70	0x0000aaaaaaabcaa8

(gdb) disas 0x0000aaaaaaaabb90
Dump of assembler code for function _ZTv0_n24_N7DerivedD1Ev:
   0x0000aaaaaaaabb90 <+0>:	ldr	x16, [x0]
   0x0000aaaaaaaabb94 <+4>:	ldur	x17, [x16, #-24]
   0x0000aaaaaaaabb98 <+8>:	add	x0, x0, x17
   0x0000aaaaaaaabb9c <+12>:	b	0xaaaaaaaabafc <Derived::~Derived()>
End of assembler dump.

(gdb) disas 0x0000aaaaaaaabbcc
Dump of assembler code for function _ZTv0_n24_N7DerivedD0Ev:
   0x0000aaaaaaaabbcc <+0>:	ldr	x16, [x0]
   0x0000aaaaaaaabbd0 <+4>:	ldur	x17, [x16, #-24]
   0x0000aaaaaaaabbd4 <+8>:	add	x0, x0, x17
   0x0000aaaaaaaabbd8 <+12>:	b	0xaaaaaaaabba8 <Derived::~Derived()>
End of assembler dump.

(gdb) disas 0x0000aaaaaaaabc0c
Dump of assembler code for function _ZTv0_n32_N7Derived3fooEv:
   0x0000aaaaaaaabc0c <+0>:	ldr	x16, [x0]
   0x0000aaaaaaaabc10 <+4>:	ldur	x17, [x16, #-32]
   0x0000aaaaaaaabc14 <+8>:	add	x0, x0, x17
   0x0000aaaaaaaabc18 <+12>:	b	0xaaaaaaaabbe4 <Derived::foo()>
End of assembler dump.

(gdb) disas 0x0000aaaaaaaab5d4
Dump of assembler code for function Base::bar():
   0x0000aaaaaaaab5d4 <+0>:	sub	sp, sp, #0x10
   0x0000aaaaaaaab5d8 <+4>:	str	x0, [sp, #8]
   0x0000aaaaaaaab5dc <+8>:	ldr	x0, [sp, #8]
   0x0000aaaaaaaab5e0 <+12>:	ldr	w0, [x0, #8]
   0x0000aaaaaaaab5e4 <+16>:	sub	w1, w0, #0x1
   0x0000aaaaaaaab5e8 <+20>:	ldr	x0, [sp, #8]
   0x0000aaaaaaaab5ec <+24>:	str	w1, [x0, #8]
   0x0000aaaaaaaab5f0 <+28>:	nop
   0x0000aaaaaaaab5f4 <+32>:	add	sp, sp, #0x10
   0x0000aaaaaaaab5f8 <+36>:	ret
End of assembler dump.
```


#### 2.4.2 对象模型
根据前面的分析，对Derived类(虚函数 + 虚继承)的实例d， 其对象模型如下

```
+-------------+            
| _vptr.Base2 |   ---->    +-------------------+
+-------------+            |Derived::~Derived()| <---------------------------
|  m_base2    |            +-------------------+                      |     |
+-------------+            |Derived::~Derived()| <--------------------|-----|--
| _vptr.Base3 |   ----     +-------------------+                      | |   | | 
+-------------+      |     |   Derived::foo()  | <--------------------|-|---|-|-- 
|  m_base3    |      |     +-------------------+                      | | | | | |
+-------------+      |                                                | | | | | |
|  m_derived  |      ----> +----------------------------------------+ | | | | | |
+-------------+            |non-virtual thunk to Derived::~Derived()|-- | | | | |
| _vptr.Base  |   ----     +----------------------------------------+   | | | | |
+-------------+      |     |non-virtual thunk to Derived::~Derived()|---- | | | |
|   m_base    |      |     +----------------------------------------+     | | | |
+-------------+      |     |  non-virtual thunk to Derived::foo()   |------ | | |
                     |     +----------------------------------------+       | | |
                     |                                                      | | |
                     ----> +------------------------------------+           | | |
                           |virtual thunk to Derived::~Derived()|------------ | |
                           +------------------------------------+             | |
                           |virtual thunk to Derived::~Derived()|-------------- |
                           +------------------------------------+               |
                           |   virtual thunk to Derived::foo()  |---------------- 
                           +------------------------------------+
                           |            Base::bar()             |
                           +------------------------------------+
```


#### 2.4.3 代码分析
**通过实例直接调用虚函数**

```cpp
d.foo();
```

反汇编如下

```asm
=> 0x0000aaaaaaaab408 <+388>:	add	x0, x29, #0xa8
   0x0000aaaaaaaab40c <+392>:	bl	0xaaaaaaaabbe4 <Derived::foo()>
```

**通过基类指针调用虚函数**

通过**Base2基类指针**访问d对象
```cpp
  Base2 *pb2 = &d;
  pb2->foo();
```

反汇编如下
```asm
   0x0000aaaaaaaab398 <+276>:	add	x0, x29, #0xa8
   0x0000aaaaaaaab39c <+280>:	str	x0, [x29, #56]
   0x0000aaaaaaaab3a0 <+284>:	ldr	x0, [x29, #56]
   
   0x0000aaaaaaaab3a4 <+288>:	ldr	x0, [x0]
   
   0x0000aaaaaaaab3a8 <+292>:	add	x0, x0, #0x10
   0x0000aaaaaaaab3ac <+296>:	ldr	x1, [x0]
   
   0x0000aaaaaaaab3b0 <+300>:	ldr	x0, [x29, #56]
   0x0000aaaaaaaab3b4 <+304>:	blr	x1
```
   
通过**Base3基类指**针访问d对象
```cpp 
  Base3 *pb3 = &d;
  pb3->foo();
```

反汇编如下
```asm
   0x0000aaaaaaaab3c0 <+316>:	add	x0, x29, #0xa8
   
   0x0000aaaaaaaab3c4 <+320>:	add	x0, x0, #0x10
   0x0000aaaaaaaab3c8 <+324>:	str	x0, [x29, #64]
   0x0000aaaaaaaab3cc <+328>:	ldr	x0, [x29, #64]
   
   0x0000aaaaaaaab3d0 <+332>:	ldr	x0, [x0]
   
   0x0000aaaaaaaab3d4 <+336>:	add	x0, x0, #0x10
   0x0000aaaaaaaab3d8 <+340>:	ldr	x1, [x0]
   
   0x0000aaaaaaaab3dc <+344>:	ldr	x0, [x29, #64]
   0x0000aaaaaaaab3e0 <+348>:	blr	x1
```

通过**Base基类指针**访问d对象
```cpp
  pb = &d;
  pb->foo();
```

反汇编如下
```asm
   0x0000aaaaaaaab3e4 <+352>:	add	x0, x29, #0xa8
   
   0x0000aaaaaaaab3e8 <+356>:	add	x0, x0, #0x20
   0x0000aaaaaaaab3ec <+360>:	str	x0, [x29, #48]
   0x0000aaaaaaaab3f0 <+364>:	ldr	x0, [x29, #48]
   
   0x0000aaaaaaaab3f4 <+368>:	ldr	x0, [x0]
   
   0x0000aaaaaaaab3f8 <+372>:	add	x0, x0, #0x10
   0x0000aaaaaaaab3fc <+376>:	ldr	x1, [x0]
   
   0x0000aaaaaaaab400 <+380>:	ldr	x0, [x29, #48]
   0x0000aaaaaaaab404 <+384>:	blr	x1
```

## 3. 总结
- 普通类的对象模型主要由vptr(虚函数) + 当前类非静态成员变量组成
- 单一继承类的对象模型主要由vptr + 基类非静态成员变量 + 派生类非静态成员变量组成
- 虚继承的对象模型最复杂, 主要由多个vptr + 直接继承类非静态成员变量 + 派生类非静态成员变量 + 虚基类非静态成员变量组成

---

![程序员自我修养](http://ww1.sinaimg.cn/large/005Kyrj9ly1gbvsonijdoj3076076wex.jpg)

<center>
程序员自我修养(ID: dumphex)
</center>

---
