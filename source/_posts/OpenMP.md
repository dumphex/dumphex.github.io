---
title: OpenMP
date: 2020-03-20 10:50:36
tags:
- Performance
- OpenMP
- omp
- GOMP_parallel

categories: Performance
---

整理一下以前使用过的OpenMP

<!-- more -->

## 1. 前言

### 1.1 基本功能
- [OpenMP(Open Multi-Processing)](https://zh.wikipedia.org/wiki/OpenMP) 
- 本质是利用**多线程**加速程序执行
- 支持C/C++/Fortran
- 支持icc/gcc等编译器

### 1.2 流程
![https://zh.wikipedia.org/wiki/OpenMP](http://ww1.sinaimg.cn/large/005Kyrj9ly1gcygax65bqj318g0ii409.jpg)


- 开发人员在代码中插入#pragma omp指令语句
- 编译器生成多线程代码
- 运行时多线程加速

> 注: 启动多线程后， 这几个线程不会退出， 将会一直存在.

### 1.3 语法
```
#pragma omp <directive> [clause[[,] clause] ...]
```

**directive**
- parallel: 后续代码块将被多线程分别执行一遍
- for: 将循环拆分(需要确保循环之间没有数据依赖)
  > parallel for: 将循环拆分到多个线程并行执行
- master: 下面语句块由master线程执行
- single: 下面语句块由单个线程执行
- barrier: 同步所有并行线程
- ... ...

**clause**
- num_threads: 设置并行线程个数
- private: 设置变量为线程私有的
- shared: 设置变量为共享的， 需要注意同步
- reduction: 指定变量先是线程私有的， 最后并行结束后归约到一起
- ... ...

### 1.4 APIs
- omp_set_num_threads(): 设置并行线程个数
- omp_get_num_threads(): 获取并行线程个数
- omp_get_thread_num(): 获取线程id(master thread为0, 其他线程为1, 2, ...)
- ... ...

### 1.5 编译
- 头文件: omp.h 
- gcc编译选项: -fopenmp
- 动态库: libgomp.so.1


## 2. 调试分析

### 2.1 测试环境
```
$ uname -a
Linux ubuntu18arm64 4.15.0-76-generic #86-Ubuntu SMP Fri Jan 17 17:25:58 UTC 2020 aarch64 aarch64 aarch64 GNU/Linux

$ g++ -v
Using built-in specs.
COLLECT_GCC=g++
COLLECT_LTO_WRAPPER=/usr/lib/gcc/aarch64-linux-gnu/7/lto-wrapper
Target: aarch64-linux-gnu
Configured with: ../src/configure -v --with-pkgversion='Ubuntu/Linaro 7.4.0-1ubuntu1~18.04.1' --with-bugurl=file:///usr/share/doc/gcc-7/README.Bugs --enable-languages=c,ada,c++,go,d,fortran,objc,obj-c++ --prefix=/usr --with-gcc-major-version-only --program-suffix=-7 --program-prefix=aarch64-linux-gnu- --enable-shared --enable-linker-build-id --libexecdir=/usr/lib --without-included-gettext --enable-threads=posix --libdir=/usr/lib --enable-nls --with-sysroot=/ --enable-clocale=gnu --enable-libstdcxx-debug --enable-libstdcxx-time=yes --with-default-libstdcxx-abi=new --enable-gnu-unique-object --disable-libquadmath --disable-libquadmath-support --enable-plugin --enable-default-pie --with-system-zlib --enable-multiarch --enable-fix-cortex-a53-843419 --disable-werror --enable-checking=release --build=aarch64-linux-gnu --host=aarch64-linux-gnu --target=aarch64-linux-gnu
Thread model: posix
gcc version 7.4.0 (Ubuntu/Linaro 7.4.0-1ubuntu1~18.04.1) 
```
### 2.2 测试源码

**CPP测试代码**
```cpp
float CPP::dotProduct(const std::vector<float> &v1,
                      const std::vector<float> &v2) {
  size_t size = v1.size();
  float mac = 0.0;

  for (size_t i = 0; i < size; i++) {
    mac += v1[i] * v2[i];
  }

  return mac;
}
```

**OpenMP测试代码**
```cpp
float OpenMP::dotProduct(const std::vector<float> &v1,
                         const std::vector<float> &v2) {
  int size = v1.size();
  float mac = 0.0;

  #pragma omp parallel for reduction(+:mac)
  for (int i = 0; i < size; i++) {
    mac += v1[i] * v2[i];
  }

  return mac;
}
```

### 2.3 测试结果
```shell
$ ./out/bin/dotProduct 
size = 256
CPP took 3267 ms
OpenMP took 6832 ms

size = 512
CPP took 5650 ms
OpenMP took 6286 ms

size = 1024
CPP took 11292 ms
OpenMP took 7374 ms

size = 2048
CPP took 22476 ms
OpenMP took 9762 ms

size = 4096
CPP took 45137 ms
OpenMP took 14522 ms

```

在该测试中可以观察到，只有当计算量超过size = 1024后， 使用OpenMP获取的收益才超过本身带来的开销。


### 2.4 OpenMP::dotProduct()

为了弄清楚OpenMP的实现原理，我们从OpenMP::dotProduct()入手, 看看编译器做了哪些操作。

反汇编如下
```asm
(gdb) disas
Dump of assembler code for function OpenMP::dotProduct(std::vector<float, std::allocator<float> > const&, std::vector<float, std::allocator<float> > const&):
   0x0000aaaaaaab5d78 <+0>:	stp	x29, x30, [sp, #-96]!
   0x0000aaaaaaab5d7c <+4>:	mov	x29, sp
   0x0000aaaaaaab5d80 <+8>:	str	x0, [x29, #40]
   0x0000aaaaaaab5d84 <+12>:	str	x1, [x29, #32]
   0x0000aaaaaaab5d88 <+16>:	str	x2, [x29, #24]
=> 0x0000aaaaaaab5d8c <+20>:	adrp	x0, 0xaaaaaaac9000
   0x0000aaaaaaab5d90 <+24>:	ldr	x0, [x0, #3992]
   0x0000aaaaaaab5d94 <+28>:	ldr	x1, [x0]
   0x0000aaaaaaab5d98 <+32>:	str	x1, [x29, #88]
   0x0000aaaaaaab5d9c <+36>:	mov	x1, #0x0                   	// #0
   0x0000aaaaaaab5da0 <+40>:	ldr	x0, [x29, #32]
   0x0000aaaaaaab5da4 <+44>:	bl	0xaaaaaaab5190 <std::vector<float, std::allocator<float> >::size() const>
   0x0000aaaaaaab5da8 <+48>:	str	w0, [x29, #56]
   0x0000aaaaaaab5dac <+52>:	str	wzr, [x29, #60]
   0x0000aaaaaaab5db0 <+56>:	ldr	s0, [x29, #60]
   0x0000aaaaaaab5db4 <+60>:	str	s0, [x29, #84]
   0x0000aaaaaaab5db8 <+64>:	ldr	w0, [x29, #56]
   0x0000aaaaaaab5dbc <+68>:	str	w0, [x29, #80]
   0x0000aaaaaaab5dc0 <+72>:	ldr	x0, [x29, #32]
   0x0000aaaaaaab5dc4 <+76>:	str	x0, [x29, #64]
   0x0000aaaaaaab5dc8 <+80>:	ldr	x0, [x29, #24]
   0x0000aaaaaaab5dcc <+84>:	str	x0, [x29, #72]
   0x0000aaaaaaab5dd0 <+88>:	add	x1, x29, #0x40
   0x0000aaaaaaab5dd4 <+92>:	adrp	x0, 0xaaaaaaab6000 <NEONIntrinsic::dotProduct(std::vector<float, std::allocator<float> > const&, std::vector<float, std::allocator<float> > const&)+484>
   0x0000aaaaaaab5dd8 <+96>:	add	x0, x0, #0xa8
   0x0000aaaaaaab5ddc <+100>:	mov	w3, #0x0                   	// #0
   0x0000aaaaaaab5de0 <+104>:	mov	w2, #0x0                   	// #0
   0x0000aaaaaaab5de4 <+108>:	bl	0xaaaaaaab26b0 <GOMP_parallel@plt>
   0x0000aaaaaaab5de8 <+112>:	ldr	s0, [x29, #84]
   0x0000aaaaaaab5dec <+116>:	str	s0, [x29, #60]
   0x0000aaaaaaab5df0 <+120>:	ldr	s0, [x29, #60]
   0x0000aaaaaaab5df4 <+124>:	adrp	x0, 0xaaaaaaac9000
   0x0000aaaaaaab5df8 <+128>:	ldr	x0, [x0, #3992]
   0x0000aaaaaaab5dfc <+132>:	ldr	x1, [x29, #88]
   0x0000aaaaaaab5e00 <+136>:	ldr	x0, [x0]
   0x0000aaaaaaab5e04 <+140>:	eor	x0, x1, x0
   0x0000aaaaaaab5e08 <+144>:	cmp	x0, #0x0
   0x0000aaaaaaab5e0c <+148>:	b.eq	0xaaaaaaab5e14 <OpenMP::dotProduct(std::vector<float, std::allocator<float> > const&, std::vector<float, std::allocator<float> > const&)+156>  // b.none
   0x0000aaaaaaab5e10 <+152>:	bl	0xaaaaaaab2570 <__stack_chk_fail@plt>
   0x0000aaaaaaab5e14 <+156>:	ldp	x29, x30, [sp], #96
   0x0000aaaaaaab5e18 <+160>:	ret
End of assembler dump.
```

调用omp相关代码如下
```asm
   0x0000aaaaaaab5dd0 <+88>:	add	x1, x29, #0x40
   0x0000aaaaaaab5dd4 <+92>:	adrp	x0, 0xaaaaaaab6000 <NEONIntrinsic::dotProduct(std::vector<float, std::allocator<float> > const&, std::vector<float, std::allocator<float> > const&)+484>
   0x0000aaaaaaab5dd8 <+96>:	add	x0, x0, #0xa8
   0x0000aaaaaaab5ddc <+100>:	mov	w3, #0x0                   	// #0
   0x0000aaaaaaab5de0 <+104>:	mov	w2, #0x0                   	// #0
   0x0000aaaaaaab5de4 <+108>:	bl	0xaaaaaaab26b0 <GOMP_parallel@plt>
```

从反汇编看，调用OMP_parallel()函数传入了4个参数
- x0 = 0xaaaaaaab6000 + 0xa8 = 0x0000aaaaaaab60a8
- x1为[fp + 0x40], 里面存放v1, 后面紧跟着存放v2/size/mac等参数
- x2为0
- x3为0


### 2.5 GOMP_parallel()
> 源文件: gcc/libgomp/parallel.c
```
void
GOMP_parallel (void (*fn) (void *), void *data, unsigned num_threads, unsigned int flags)
{
  num_threads = gomp_resolve_num_threads (num_threads, 0); 
  gomp_team_start (fn, data, num_threads, flags, gomp_new_team (num_threads));
  fn (data);
  ialias_call (GOMP_parallel_end) (); 
}
```

主要操作如下
- gomp_resolve_num_threads(): 获取指定的线程个数或默认的线程个数
- gomp_team_start(): 启动线程池(num_threads - 1个线程)
- fn(): master thread调用fn()
- GOMP_parallel_end(): omp调用结束


可以看到，OpenMP的每个线程都调用到了fn()函数, 这个函数就是前面提到的x0 = 0x0000aaaaaaab60a8

### 2.6 clone ._omp_fn.0

这个函数是编译器根据OpenMP::dotProduct()修改生成的clone函数

先反汇编看一下
```asm
(gdb) disas 0x0000aaaaaaab60a8
Dump of assembler code for function _ZN6OpenMP10dotProductERKSt6vectorIfSaIfEES4_._omp_fn.0(void):
   0x0000aaaaaaab60a8 <+0>:	stp	x29, x30, [sp, #-80]!
   0x0000aaaaaaab60ac <+4>:	mov	x29, sp
   0x0000aaaaaaab60b0 <+8>:	stp	x19, x20, [sp, #16]
   0x0000aaaaaaab60b4 <+12>:	str	d8, [sp, #32]
   0x0000aaaaaaab60b8 <+16>:	str	x0, [x29, #56]
   0x0000aaaaaaab60bc <+20>:	str	wzr, [x29, #68]
   0x0000aaaaaaab60c0 <+24>:	ldr	x0, [x29, #56]
   0x0000aaaaaaab60c4 <+28>:	ldr	w0, [x0, #16]
   0x0000aaaaaaab60c8 <+32>:	str	w0, [x29, #76]
   0x0000aaaaaaab60cc <+36>:	ldr	w19, [x29, #76]
   0x0000aaaaaaab60d0 <+40>:	bl	0xaaaaaaab2750 <omp_get_num_threads@plt>
   0x0000aaaaaaab60d4 <+44>:	mov	w20, w0
   0x0000aaaaaaab60d8 <+48>:	bl	0xaaaaaaab26d0 <omp_get_thread_num@plt>
   0x0000aaaaaaab60dc <+52>:	mov	w2, w0
   0x0000aaaaaaab60e0 <+56>:	sdiv	w0, w19, w20
   0x0000aaaaaaab60e4 <+60>:	sdiv	w1, w19, w20
   0x0000aaaaaaab60e8 <+64>:	mul	w1, w1, w20
   0x0000aaaaaaab60ec <+68>:	sub	w1, w19, w1
   0x0000aaaaaaab60f0 <+72>:	cmp	w2, w1
   0x0000aaaaaaab60f4 <+76>:	b.lt	0xaaaaaaab61ac <_ZN6OpenMP10dotProductERKSt6vectorIfSaIfEES4_._omp_fn.0(void)+260>  // b.tstop
   0x0000aaaaaaab60f8 <+80>:	mul	w2, w0, w2
   0x0000aaaaaaab60fc <+84>:	add	w1, w2, w1
   0x0000aaaaaaab6100 <+88>:	add	w19, w1, w0
   0x0000aaaaaaab6104 <+92>:	cmp	w1, w19
   0x0000aaaaaaab6108 <+96>:	b.ge	0xaaaaaaab6160 <_ZN6OpenMP10dotProductERKSt6vectorIfSaIfEES4_._omp_fn.0(void)+184>  // b.tcont
   0x0000aaaaaaab610c <+100>:	str	w1, [x29, #72]
   0x0000aaaaaaab6110 <+104>:	ldrsw	x1, [x29, #72]
   0x0000aaaaaaab6114 <+108>:	ldr	x0, [x29, #56]
   0x0000aaaaaaab6118 <+112>:	ldr	x0, [x0]
   0x0000aaaaaaab611c <+116>:	bl	0xaaaaaaab6370 <std::vector<float, std::allocator<float> >::operator[](unsigned long) const>
   0x0000aaaaaaab6120 <+120>:	ldr	s8, [x0]
   0x0000aaaaaaab6124 <+124>:	ldrsw	x1, [x29, #72]
   0x0000aaaaaaab6128 <+128>:	ldr	x0, [x29, #56]
   0x0000aaaaaaab612c <+132>:	ldr	x0, [x0, #8]
   0x0000aaaaaaab6130 <+136>:	bl	0xaaaaaaab6370 <std::vector<float, std::allocator<float> >::operator[](unsigned long) const>
   0x0000aaaaaaab6134 <+140>:	ldr	s0, [x0]
   0x0000aaaaaaab6138 <+144>:	fmul	s0, s8, s0
   0x0000aaaaaaab613c <+148>:	ldr	s1, [x29, #68]
   0x0000aaaaaaab6140 <+152>:	fadd	s0, s1, s0
   0x0000aaaaaaab6144 <+156>:	str	s0, [x29, #68]
   0x0000aaaaaaab6148 <+160>:	ldr	w0, [x29, #72]
   0x0000aaaaaaab614c <+164>:	add	w0, w0, #0x1
   0x0000aaaaaaab6150 <+168>:	str	w0, [x29, #72]
   0x0000aaaaaaab6154 <+172>:	ldr	w0, [x29, #72]
   0x0000aaaaaaab6158 <+176>:	cmp	w0, w19
   0x0000aaaaaaab615c <+180>:	b.lt	0xaaaaaaab6110 <_ZN6OpenMP10dotProductERKSt6vectorIfSaIfEES4_._omp_fn.0+104>  // b.tstop
   0x0000aaaaaaab6160 <+184>:	ldr	x0, [x29, #56]
   0x0000aaaaaaab6164 <+188>:	add	x0, x0, #0x14
   0x0000aaaaaaab6168 <+192>:	mov	x1, x0
   0x0000aaaaaaab616c <+196>:	ldr	w0, [x1]
   0x0000aaaaaaab6170 <+200>:	fmov	s1, w0
   0x0000aaaaaaab6174 <+204>:	ldr	s0, [x29, #68]
   0x0000aaaaaaab6178 <+208>:	fadd	s0, s1, s0
   0x0000aaaaaaab617c <+212>:	fmov	w3, s0
   0x0000aaaaaaab6180 <+216>:	ldxr	w2, [x1]
   0x0000aaaaaaab6184 <+220>:	cmp	w2, w0
   0x0000aaaaaaab6188 <+224>:	b.ne	0xaaaaaaab6194 <_ZN6OpenMP10dotProductERKSt6vectorIfSaIfEES4_._omp_fn.0(void)+236>  // b.any
   0x0000aaaaaaab618c <+228>:	stlxr	w4, w3, [x1]
   0x0000aaaaaaab6190 <+232>:	cbnz	w4, 0xaaaaaaab6180 <_ZN6OpenMP10dotProductERKSt6vectorIfSaIfEES4_._omp_fn.0(void)+216>
   0x0000aaaaaaab6194 <+236>:	dmb	ish
   0x0000aaaaaaab6198 <+240>:	mov	w3, w0
   0x0000aaaaaaab619c <+244>:	mov	w0, w2
   0x0000aaaaaaab61a0 <+248>:	cmp	w2, w3
   0x0000aaaaaaab61a4 <+252>:	b.ne	0xaaaaaaab6170 <_ZN6OpenMP10dotProductERKSt6vectorIfSaIfEES4_._omp_fn.0(void)+200>  // b.any
   0x0000aaaaaaab61a8 <+256>:	b	0xaaaaaaab61b8 <_ZN6OpenMP10dotProductERKSt6vectorIfSaIfEES4_._omp_fn.0(void)+272>
   0x0000aaaaaaab61ac <+260>:	mov	w1, #0x0                   	// #0
   0x0000aaaaaaab61b0 <+264>:	add	w0, w0, #0x1
   0x0000aaaaaaab61b4 <+268>:	b	0xaaaaaaab60f8 <_ZN6OpenMP10dotProductERKSt6vectorIfSaIfEES4_._omp_fn.0+80>
   0x0000aaaaaaab61b8 <+272>:	ldp	x19, x20, [sp, #16]
   0x0000aaaaaaab61bc <+276>:	ldr	d8, [sp, #32]
   0x0000aaaaaaab61c0 <+280>:	ldp	x29, x30, [sp], #80
   0x0000aaaaaaab61c4 <+284>:	ret
End of assembler dump.
```

主要操作如下
- 根据for循环的循环次数/当前的线程个数/当前线程ID， 确定当前thread要完成的任务
- 执行本线程分配的循环部分
- 将计算结果写回mac(注意多线程之间的数据同步)


## 3. 总结
- OpenMP利用多线程进行加速，但本身线程的启动也有开销，具体使用时需要tradeoff
- OpenMP使用时需要注意循环之间的依赖关系/数据竞争等，调试上不太方便

---

![程序员自我修养](http://ww1.sinaimg.cn/large/005Kyrj9ly1gbvsonijdoj3076076wex.jpg)

<center>
程序员自我修养(ID: dumphex)
</center>

---
